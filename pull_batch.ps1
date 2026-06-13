param(
    [Parameter(Mandatory)][string]$Category,
    [Parameter(Mandatory)][int]$Count,
    [string]$StartFrom = "",
    [string]$ProgressFile = (Join-Path $PSScriptRoot "拉取进度.json"),
    [string]$KeysFile = (Join-Path $PSScriptRoot ".keys.json"),
    [string]$LogDir = (Join-Path $PSScriptRoot "batch_log"),
    [string]$BackupDir = (Join-Path $PSScriptRoot "_backup\progress"),
    [string]$TmpDir = (Join-Path $PSScriptRoot "_tmp"),
    [string]$KeyId = "",
    [int]$DailyQuota = 1000,
    [switch]$ForceReclaim
)

$ErrorActionPreference = "Stop"
$devName = $env:COMPUTERNAME
$now = Get-Date
$ts = $now.ToString("yyyyMMddTHHmmssZ")
$logFile = "$LogDir\$($now.ToString('yyyyMMdd')).log"
if (-not [System.IO.Directory]::Exists($LogDir)) { [System.IO.Directory]::CreateDirectory($LogDir) | Out-Null }

function Log($msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss') [$devName] $msg"
    Write-Host $line
    [System.IO.File]::AppendAllText($logFile, "$line`r`n", [System.Text.UTF8Encoding]::new($true))
}

# ===== 3a. -KeyId + .keys.json =====
if (-not [System.IO.File]::Exists($KeysFile)) { throw "Keys file not found: $KeysFile" }
$kj = [System.IO.File]::ReadAllText($KeysFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
if (-not $KeyId) { $KeyId = $kj.defaultKeyId }
$keyEntry = $kj.keys | Where-Object { $_.id -eq $KeyId }
if (-not $keyEntry) { throw "KeyId not found in .keys.json: $KeyId" }
$env:WIND_API_KEY = $keyEntry.value
Log "Using KeyId: $KeyId (ak_***$($keyEntry.value.Substring($keyEntry.value.Length-4)))"

# ===== 9.5 清残留 .tmp =====
$tmpFile = "$ProgressFile.tmp"
if ([System.IO.File]::Exists($tmpFile)) {
    [System.IO.File]::Delete($tmpFile)
    Log "清理残留 .tmp: $tmpFile"
}

# ===== 9.1 try-parse 进度文件 =====
$stockListFile = Join-Path $PSScriptRoot "lists\stock_list.csv"
if (-not [System.IO.File]::Exists($ProgressFile)) {
    if (-not [System.IO.File]::Exists($stockListFile)) {
        throw "Progress file not found: $ProgressFile (also stock_list.csv missing, cannot auto-init)"
    }
    Log "进度文件不存在, 从 stock_list.csv 初始化..."
    $validCats = @('sh_main','sz_main','chinext','star','sme','etf','index')
    $categories = [ordered]@{}
    $stocks = [ordered]@{}
    foreach ($cat in $validCats) { $categories[$cat] = [ordered]@{ total=0; completed=0; failed=0; pending=0 } }
    $lines = [System.IO.File]::ReadAllLines($stockListFile, [System.Text.Encoding]::UTF8)
    foreach ($line in $lines[1..($lines.Count-1)]) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line.Split(',')
        $cat = $parts[0].Trim()
        $windCode = $parts[1].Trim()
        if ($validCats -notcontains $cat) { continue }
        $exch = if ($windCode.EndsWith('.SH')) { 'sh' } elseif ($windCode.EndsWith('.SZ')) { 'sz' } else { continue }
        $numeric = $windCode.Substring(0, $windCode.IndexOf('.'))
        $internalCode = "$exch.$numeric"
        $stocks[$internalCode] = [ordered]@{
            status = 'pending'
            category = $cat
            windCode = $windCode
            server = $null
            updatedBy = $null
            updatedAt = $null
            error = $null
            failCount = $null
            rows = $null
            file = $null
            firstDate = $null
            lastDate = $null
            leaseUntil = $null
            heartbeatAt = $null
            claimedAt = $null
            claimedBy = $null
            historyStatus = $null
            historyReason = $null
            needsManualReview = $false
        }
        $categories[$cat].total++
        $categories[$cat].pending++
    }
    $progress = [ordered]@{
        lastUpdatedBy = $devName
        version = '1.3'
        lastUpdatedAt = (Get-Date).ToString('o')
        categories = $categories
        stocks = $stocks
    }
    $json = $progress | ConvertTo-Json -Depth 10
    $tmpInit = "$ProgressFile.tmp"
    [System.IO.File]::WriteAllText($tmpInit, $json, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::Move($tmpInit, $ProgressFile)
    Log "初始化完成: $($stocks.Count) 只证券, 来源: stock_list.csv"
} else {
$progressContent = [System.IO.File]::ReadAllText($ProgressFile, [System.Text.Encoding]::UTF8)
try {
    $progress = $progressContent | ConvertFrom-Json
} catch {
    $latestBak = Get-ChildItem $BackupDir -Filter "*.bak_pre_batch_*.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestBak) {
        [System.IO.File]::Copy($latestBak.FullName, $ProgressFile, $true)
        $progress = [System.IO.File]::ReadAllText($ProgressFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        Log "WARN: 进度文件 parse 失败, 从备份还原: $($latestBak.Name)"
    } else {
        throw "进度文件 parse 失败且无备份: $_"
    }
}
}

# ===== 9.6 BOM 检查 =====
$firstBytes = [System.IO.File]::ReadAllBytes($ProgressFile)[0..2]
if ($firstBytes[0] -eq 0xEF -and $firstBytes[1] -eq 0xBB -and $firstBytes[2] -eq 0xBF) {
    throw "进度文件含 BOM, 不允许: $ProgressFile"
}

# ===== 9.2 pre-batch 备份 =====
if (-not [System.IO.Directory]::Exists($BackupDir)) { [System.IO.Directory]::CreateDirectory($BackupDir) | Out-Null }
$preBak = "$BackupDir\拉取进度.json.bak_pre_batch_$ts.json"
[System.IO.File]::Copy($ProgressFile, $preBak, $true)
Log "pre-batch 备份: $preBak"

# ===== 3f. 磁盘预估 =====
$pendingCount = ($progress.stocks.PSObject.Properties.Value | Where-Object { $_.status -eq 'pending' }).Count
$driveRoot = [System.IO.Path]::GetPathRoot($ProgressFile)[0]
try {
    $driveInfo = Get-PSDrive -Name $driveRoot -ErrorAction Stop
    $diskFreeGB = [math]::Round($driveInfo.Free / 1GB, 1)
    $csvDir = Join-Path $PSScriptRoot "A-shares"
    $csvSamples = @(Get-ChildItem $csvDir -Filter "*.csv" -ErrorAction SilentlyContinue | Get-Random -Count 5)
    $avgBytes = if ($csvSamples.Count -gt 0) {
        ($csvSamples | ForEach-Object { $_.Length } | Measure-Object -Average).Average
    } else {
        302592  # 295.5KB fallback
    }
    $diskEstimatedGB = [math]::Round($avgBytes * $pendingCount / 1GB, 2)
    Log "磁盘预估: pending=$pendingCount avg=$([math]::Round($avgBytes/1KB,1))KB -> ~${diskEstimatedGB}GB (free=${diskFreeGB}GB)"
    if ($diskFreeGB -lt 3) { Log "WARN: 磁盘空间不足: free=${diskFreeGB}GB < 3GB" }
} catch {
    Log "磁盘预估: skipped (无法读取磁盘信息)"
    $diskEstimatedGB = "N/A"
    $diskFreeGB = "N/A"
}

# ===== 9.3 19 字段校验 =====
$sample10 = @($progress.stocks.PSObject.Properties.Value | Get-Random -Count 10)
$schemaOk = $true
foreach ($e in $sample10) {
    $f = $e.PSObject.Properties.Name
    if ($f.Count -ne 19) { $schemaOk = $false; Log "  ❌ wc=$($e.windCode) fields=$($f.Count)" }
}
if (-not $schemaOk) { throw "进度文件 schema 不符 (期望 19 字段)" }
Log "19 字段校验: ✅ (抽样 10 entry 全 19 字段)"

# ===== 9.4 category 一致 =====
$validCats = @('sh_main','sz_main','chinext','star','sme','etf','index')
if ($validCats -notcontains $Category) { throw "Unknown category: $Category" }

# ===== 9.7-9.8 当日 Wind 计数 + 锁扫描 =====
$todayFile = "$TmpDir\.today_count"
$todayKey = (Get-Date -Format "yyyyMMdd")
$todayCount = 0
if ([System.IO.File]::Exists($todayFile)) {
    $tc = [System.IO.File]::ReadAllText($todayFile, [System.Text.Encoding]::UTF8) -split '\|'
    if ($tc[0] -eq $todayKey) { $todayCount = [int]$tc[1] }
}
$todayCount += $Count
$quotaLeft = $DailyQuota - $todayCount
if ($quotaLeft -lt $Count) { Log "INFO: 本日 Wind 计数: 已用 $todayCount / $DailyQuota, 本批 $Count" }
Log "当日 Wind 调用计数: $todayCount / $DailyQuota"

$nowUtc = (Get-Date).ToUniversalTime()
$staleActive = @()
$historicalTraces = 0
foreach ($prop in $progress.stocks.PSObject.Properties) {
    $s = $prop.Value
    if ($s.claimedBy -and $s.leaseUntil) {
        try {
            $lu = [datetime]$s.leaseUntil
            if ($lu -lt $nowUtc) {
                if ($s.status -in @('in_progress','claimed')) { $staleActive += $prop.Name }
                elseif ($s.status -eq 'success') { $historicalTraces++ }
            }
        } catch {}
    }
}
if ($staleActive.Count -gt 0) {
    Log "⚠️ 活跃锁扫描: $($staleActive.Count) 条过期锁"
    $staleActive | Select-Object -First 5 | ForEach-Object { Log "    $_" }
    if ($staleActive.Count -gt 5) { Log "    ... (省略 $($staleActive.Count - 5) 条)" }
    Log "  → 未自动回收, 需 -ForceReclaim 接管"
}
Log "活跃锁: $($staleActive.Count) | 历史锁 trace: $historicalTraces (不报警)"

# ===== 业务逻辑（清僵尸锁 / 选 pending / 跑 batch）=====
foreach ($key in @($progress.stocks.PSObject.Properties.Name)) {
    $s = $progress.stocks.$key
    if ($s.status -eq 'in_progress' -and $s.claimedAt -and -not $ForceReclaim) {
        $claimedAt = [datetime]$s.claimedAt
        if (($now - $claimedAt).TotalMinutes -gt 30) {
            $s.status = 'pending'; $s.claimedBy = $null; $s.claimedAt = $null
        }
    } elseif ($ForceReclaim -and $s.status -eq 'in_progress') {
        $s.status = 'pending'; $s.claimedBy = $null; $s.claimedAt = $null
        Log "ForceReclaim 释放: $key"
    }
}

function Parse-Symbol($sym) {
    $parts = $sym.Split('.')
    $exch = $parts[1].ToLower()
    $exchMap = @{ 'sh' = 'sh'; 'sz' = 'sz' }
    $exchShort = $exchMap[$exch]
    if (-not $exchShort) { throw "Unknown exchange suffix: $sym" }
    return @{ Exchange = $exchShort; Code = $parts[0] }
}

function Get-Server($cat) {
    switch ($cat) {
        { $_ -in 'sh_main','sz_main','chinext','star','sme' } { return @{ Srv='stock_data'; Tool='get_stock_kline' } }
        'etf'   { return @{ Srv='fund_data';   Tool='get_fund_kline' } }
        'index' { return @{ Srv='index_data';  Tool='get_index_kline' } }
        default { throw "Unknown category: $cat" }
    }
}

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

$success = 0; $failed = 0; $abortByRate = $false

$nodePath = (Get-Command node.exe -ErrorAction Stop).Source
foreach ($internalCode in $batch) {
    $stock = $progress.stocks.$internalCode
    $sym = Parse-Symbol $stock.windCode
    $srv = Get-Server $Category

    $stock.status = 'in_progress'
    $stock.claimedBy = "$devName`:$KeyId"
    $stock.claimedAt = (Get-Date).ToString('o')
    $stock.leaseUntil = (Get-Date).AddSeconds($Count * 5 + 60).ToString('o')
    $stock.heartbeatAt = $null
    $progressJson = $progress | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($tmpFile, $progressJson, (New-Object System.Text.UTF8Encoding($false)))
    if ([System.IO.File]::Exists($ProgressFile)) { [System.IO.File]::Delete($ProgressFile) }
    [System.IO.File]::Move($tmpFile, $ProgressFile)

    Log "拉取: $internalCode ($($stock.windCode)) via $($srv.Srv)"

    try {
        $nodePathJs = $nodePath.Replace('\', '/')
        $cliMjs = (Join-Path $PSScriptRoot '.agents\skills\wind-mcp-skill\scripts\cli.mjs').Replace('\', '/')
        $windcode = $stock.windCode
        $callScript = @"
const { spawnSync } = require('child_process');
const params = '{"windcode":"$windcode","begin_date":"19900101","end_date":"20261231","period":"10","aftype":"0"}';
const cliPath = '$cliMjs';
const result = spawnSync('$nodePathJs', [cliPath, 'call', '$($srv.Srv)', '$($srv.Tool)', params], {
  encoding: 'utf8',
  maxBuffer: 10 * 1024 * 1024,
  shell: false
});
if (result.error) { process.stdout.write(JSON.stringify({isError:true,message:result.error.message})); process.exit(1); }
if (result.status !== 0) { process.stdout.write(JSON.stringify({isError:true,status:result.status,stderr:result.stderr})); process.exit(1); }
process.stdout.write(result.stdout);
"@
        $callScript | Out-File -FilePath "$TmpDir\temp_call.js" -Encoding UTF8 -NoNewline
        $raw = & "$nodePath" "$TmpDir\temp_call.js" 2>&1 | Out-String
        $rawText = $raw.Trim()
        $jsonStart = $rawText.IndexOf('{')
        if ($jsonStart -ge 0) { $rawText = $rawText.Substring($jsonStart) }
        if ($rawText -match '"isError"\s*:\s*true') {
            throw "Wind returned isError=true: $($rawText.Substring(0, [Math]::Min(200, $rawText.Length)))"
        }

        $dir = switch ($Category) { 'etf' { 'etf' } 'index' { 'index' } default { 'A-shares' } }
        $outPath = Join-Path $PSScriptRoot "$dir\$($sym.Exchange)_$($sym.Code).csv"
        & (Join-Path $PSScriptRoot "convert_kline.ps1") -JsonText $rawText -Exchange $sym.Exchange -Code $sym.Code -OutputPath $outPath | Out-Null

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
        $stock.updatedBy = "$devName`:$KeyId"
        $stock.server = $srv.Srv
        $stock.error = $null
        $stock.claimedBy = $null
        $stock.claimedAt = $null
        $stock.leaseUntil = (Get-Date).AddMinutes(30).ToString('o')
        $stock.heartbeatAt = $null
        $stock.historyStatus = if ($rowCount -ge 100) { 'normal' } elseif ($rowCount -gt 0) { 'short_history' } else { 'no_data_candidate' }
        $stock.failCount = $null
        $stock.historyReason = if ($rowCount -eq 0) { '新上市/已退市/暂无数据' } else { $null }
        $stock.needsManualReview = ($rowCount -lt 100)
        $success++

        Log "  success: $internalCode rows=$rowCount [$firstDate..$lastDate] hs=$($stock.historyStatus)"
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
        $stock.updatedBy = "$devName`:$KeyId"
        $stock.claimedBy = $null
        $stock.claimedAt = $null
        $stock.leaseUntil = (Get-Date).AddMinutes(30).ToString('o')
        $stock.heartbeatAt = $null
        $stock.historyStatus = 'failed'
        $stock.historyReason = "failed: $errMsg"
        $stock.needsManualReview = $true
        $failed++
    }

    $progressJson = $progress | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($tmpFile, $progressJson, (New-Object System.Text.UTF8Encoding($false)))
    if ([System.IO.File]::Exists($ProgressFile)) { [System.IO.File]::Delete($ProgressFile) }
    [System.IO.File]::Move($tmpFile, $ProgressFile)

    if (($success + $failed) -ge 10 -and $failed / ($success + $failed) -gt 0.1) {
        Log "ABORT: 失败率 >10% ($failed/$($success+$failed))"
        $abortByRate = $true; break
    }
    Start-Sleep -Seconds 2
}

# ===== categories 同步 =====
$catData = $progress.categories.$Category
$catData.completed = @($progress.stocks.PSObject.Properties.Value | Where-Object { $_.category -eq $Category -and $_.status -eq 'success' }).Count
$catData.failed    = @($progress.stocks.PSObject.Properties.Value | Where-Object { $_.category -eq $Category -and $_.status -eq 'abandoned' }).Count
$catData.pending   = @($progress.stocks.PSObject.Properties.Value | Where-Object { $_.category -eq $Category -and $_.status -eq 'pending' }).Count

# 写当日 Wind 调用计数
if (-not [System.IO.Directory]::Exists($TmpDir)) { [System.IO.Directory]::CreateDirectory($TmpDir) | Out-Null }
[System.IO.File]::WriteAllText($todayFile, "$todayKey|$todayCount", [System.Text.UTF8Encoding]::new($false))

# ===== 3g. 自检报告 =====
$totalEntry = @($progress.stocks.PSObject.Properties).Count
$pendingNow = @($progress.stocks.PSObject.Properties.Value | Where-Object { $_.status -eq 'pending' }).Count
$successNow = @($progress.stocks.PSObject.Properties.Value | Where-Object { $_.status -eq 'success' }).Count
$abandonedNow = @($progress.stocks.PSObject.Properties.Value | Where-Object { $_.status -eq 'abandoned' }).Count
$gradingNormal = @($progress.stocks.PSObject.Properties.Value | Where-Object { $_.historyStatus -eq 'normal' }).Count
$gradingShort = @($progress.stocks.PSObject.Properties.Value | Where-Object { $_.historyStatus -eq 'short_history' }).Count
$gradingNoData = @($progress.stocks.PSObject.Properties.Value | Where-Object { $_.historyStatus -eq 'no_data_candidate' }).Count
$reviewQueueCount = 0
$queueFile = Join-Path $PSScriptRoot "拉取进度.review_queue.json"
if ([System.IO.File]::Exists($queueFile)) {
    $rq = [System.IO.File]::ReadAllText($queueFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $reviewQueueCount = @($rq.PSObject.Properties).Count
}

Log "--- 自检报告 ---"
Log "  batch:    success=$success failed=$failed aborted=$abortByRate"
Log "  progress: total=$totalEntry pending=$pendingNow success=$successNow abandoned=$abandonedNow"
Log "  grading:  normal=$gradingNormal short_history=$gradingShort no_data_candidate=$gradingNoData"
Log "  disk:     estimated=~${diskEstimatedGB}GB free=${diskFreeGB}GB"
Log "  schema:   19 fields verified at start"
Log "  lock:     active=$($staleActive.Count) hist=$historicalTraces"
Log "  today:    $todayCount / $DailyQuota (quota left=$($quotaLeft - 0))"
if ($reviewQueueCount -gt 0) { Log "  review:   $reviewQueueCount entries in review_queue.json" }
Log "  baseline: progress.json=$(if([System.IO.File]::Exists($ProgressFile)){(Get-Item $ProgressFile).Length}else{'N/A'}) bytes  pull_batch.ps1=$(Get-Item $PSCommandPath | Select-Object -ExpandProperty Length) bytes"
Log "Batch 收尾: success=$success failed=$failed"
# ===== 3h. review_queue 集成 =====
& (Join-Path $PSScriptRoot "review_queue.ps1") -ProgressFile $ProgressFile -QueueFile $queueFile
if ($abortByRate) { exit 2 } else { exit 0 }