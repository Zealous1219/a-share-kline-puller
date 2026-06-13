$pf = Join-Path $PSScriptRoot "拉取进度.json"
$j = Get-Content -LiteralPath $pf -Raw -Encoding UTF8 | ConvertFrom-Json

$catBreak = [ordered]@{}
foreach ($cat in @('sh_main','sz_main','chinext','star','sme','etf','index')) {
    $all = @($j.stocks.PSObject.Properties.Name | Where-Object { $j.stocks.$_.category -eq $cat })
    $catBreak[$cat] = [ordered]@{
        total     = $all.Count
        completed = @($all | Where-Object { $j.stocks.$_.status -eq 'success' }).Count
        failed    = @($all | Where-Object { $j.stocks.$_.status -in 'failed','abandoned' }).Count
        pending   = @($all | Where-Object { $j.stocks.$_.status -eq 'pending' }).Count
    }
}

$j.totals = $catBreak
$j.lastUpdatedAt = (Get-Date).ToString('o')
$j.lastUpdatedBy = $env:COMPUTERNAME

$utf8NoBom = New-Object System.Text.UTF8Encoding($False)
$tmpPath = "$pf.tmp"
$json = $j | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($tmpPath, $json, $utf8NoBom)
Move-Item -LiteralPath $tmpPath -Destination $pf -Force

Write-Host "totals 修复完成"