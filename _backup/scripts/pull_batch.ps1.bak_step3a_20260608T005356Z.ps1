param(
    [Parameter(Mandatory)][string]$Category,
    [Parameter(Mandatory)][int]$Count,
    [string]$StartFrom = "",
    [string]$ProgressFile = "D:\data\拉取进度.json"
)

$ErrorActionPreference = "Stop"
$devName = $env:COMPUTERNAME
$today = Get-Date -Format "yyyyMMdd"
$logDir = "D:\data\batch_log"
$logFile = "$logDir\$today.log"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

function Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') [$devName] $msg"
    Write-Host $line
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

# 解析 symbol -> exchange, code
function Parse-Symbol($sym) {
    $parts = $sym.Split('.')
    $exch = $parts[1].ToLower()
    $exchMap = @{ 'sh' = 'sh'; 'sz' = 'sz' }
    $exchShort = $exchMap[$exch]
    if (-not $exchShort) { throw "Unknown exchange suffix: $sym" }
    return @{ Exchange = $exchShort; Code = $parts[0] }
}

# 选服务器
function Get-Server($cat) {
    switch ($cat) {
        { $_ -in 'sh_main','sz_main','chinext','star','sme' } { return @{ Srv='stock_data'; Tool='get_stock_kline' } }
        'etf'   { return @{ Srv='fund_data';   Tool='get_fund_kline' } }
        'index' { return @{ Srv='index_data';  Tool='get_index_kline' } }
        default { throw "Unknown category: $cat" }
    }
}

# 读进度
$progress = Get-Content -LiteralPath $ProgressFile -Raw -Encoding UTF8 | ConvertFrom-Json

# 清僵尸锁（>30 分钟）
$now = Get-Date
foreach ($key in @($progress.stocks.PSObject.Properties.Name)) {
    $s = $progress.stocks.$key
    if ($s.status -eq 'in_progress' -and $s.claimedAt) {
        $claimedAt = [datetime]$s.claimedAt
        if (($now - $claimedAt).TotalMinutes -gt 30) {
            Log "清理僵尸锁: $key (was held by $($s.claimedBy) at $($s.claimedAt))"
            $s.status = 'pending'
            $s.claimedBy = $null
            $s.claimedAt = $null
        }
    }
}

# 选 pending
$pending = @()
foreach ($key in @($progress.stocks.PSObject.Properties.Name)) {
    $s = $progress.stocks.$key
    if ($s.category -eq $Category -and $s.status -eq 'pending') { $pending += $key }
}
$pending = $pending | Sort-Object

if ($StartFrom) {
    $i = $pending.IndexOf($StartFrom)
    if ($i -lt 0) { throw "StartFrom code not found in pending: $StartFrom" }
    $pending = $pending[$i..($pending.Count-1)]
}

$batch = $pending | Select-Object -First $Count
Log "Batch 启动: category=$Category count=$Count (queue=$($pending.Count))"

$success = 0
$failed = 0
$abortByRate = $false

foreach ($internalCode in $batch) {
    $stock = $progress.stocks.$internalCode
    $sym = Parse-Symbol $stock.windCode
    $srv = Get-Server $Category

    # claim
    $stock.status = 'in_progress'
    $stock.claimedBy = $devName
    $stock.claimedAt = (Get-Date).ToString('o')
    $progress | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ProgressFile -Encoding UTF8

    Log "拉取: $internalCode ($($stock.windCode)) via $($srv.Srv)"

    try {
        $windcode = $stock.windCode
        $callScript = @"
const { execSync } = require('child_process');
const params = '{"windcode":"$windcode","begin_date":"19900101","end_date":"20261231","period":"10","aftype":"0"}';
const cmd = 'node scripts/cli.mjs call $($srv.Srv) $($srv.Tool) "' + params.replace(/"/g, '\\"') + '"';
const result = execSync(cmd, { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 });
process.stdout.write(result);
"@
        $callScript | Out-File -FilePath "D:\data\temp_call.js" -Encoding UTF8 -NoNewline
        $raw = node D:\data\temp_call.js 2>&1 | Out-String
        $rawText = $raw.Trim()
        
        $jsonStart = $rawText.IndexOf('{')
        if ($jsonStart -ge 0) { $rawText = $rawText.Substring($jsonStart) }
        
        if ($rawText -match '"isError"\s*:\s*true') {
            throw "Wind returned isError=true: $($rawText.Substring(0, [Math]::Min(200, $rawText.Length)))"
        }

        $dir = switch ($Category) {
            'etf'   { 'etf' }
            'index' { 'index' }
            default { 'A-shares' }
        }
        $outPath = "D:\data\$dir\$($sym.Exchange)_$($sym.Code).csv"
        & D:\data\convert_kline.ps1 -JsonText $rawText -Exchange $sym.Exchange -Code $sym.Code -OutputPath $outPath | Out-Null

        $lines = Get-Content -LiteralPath $outPath
        $rowCount = if ($lines.Count -gt 1) { $lines.Count - 1 } else { 0 }
        $firstDate = if ($rowCount -gt 0) { ($lines[1] -split ',')[0] } else { $null }
        $lastDate  = if ($rowCount -gt 0) { ($lines[-1] -split ',')[0] } else { $null }

        $stock.status = 'success'
        $stock.file = "$dir\$($sym.Exchange)_$($sym.Code).csv"
        $stock.rows = $rowCount
        $stock.firstDate = $firstDate
        $stock.lastDate = $lastDate
        $stock.updatedAt = (Get-Date).ToString('o')
        $stock.updatedBy = $devName
        $stock.server = $srv.Srv
        $stock.error = $null
        $stock.claimedBy = $null
        $stock.claimedAt = $null
        $success++

        Log "  success: $internalCode rows=$rowCount [$firstDate..$lastDate]"

        if ($rowCount -eq 0) { Log "  NOTE: 0 rows (新上市/已退市)" }
    } catch {
        $errMsg = $_.Exception.Message
        $stock.failCount = if ($stock.failCount) { $stock.failCount + 1 } else { 1 }
        if ($stock.failCount -ge 3) {
            $stock.status = 'abandoned'
            Log "  ABANDONED (3 次失败): $internalCode"
        } else {
            $stock.status = 'pending'
            Log "  failed (try $($stock.failCount)/3): $internalCode - $errMsg"
        }
        $stock.error = $errMsg
        $stock.updatedAt = (Get-Date).ToString('o')
        $stock.updatedBy = $devName
        $stock.claimedBy = $null
        $stock.claimedAt = $null
        $failed++
    }

    $progress | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ProgressFile -Encoding UTF8

    if (($success + $failed) -ge 10 -and $failed / ($success + $failed) -gt 0.1) {
        Log "ABORT: 失败率 >10% ($failed/$($success+$failed))"
        $abortByRate = $true
        break
    }

    Start-Sleep -Seconds 2
}

Log "Batch 收尾: success=$success failed=$failed"
if ($abortByRate) { exit 2 } else { exit 0 }
