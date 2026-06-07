$pf = "D:\data\拉取进度.json"
$j = Get-Content -LiteralPath $pf -Raw -Encoding UTF8 | ConvertFrom-Json

$catTotals = [ordered]@{}
foreach ($key in @($j.totals.PSObject.Properties.Name)) {
    if ($key -notin @('all','success','pending','failed','in_progress','abandoned')) {
        $catTotals[$key] = $j.totals.$key
    }
}

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

$j.lastUpdatedAt = (Get-Date).ToString('o')
$j.lastUpdatedBy = $env:COMPUTERNAME
$j.totals = $catTotals
$j.categories = $catBreak

$j | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $pf -Encoding UTF8
Write-Host "Progress file fixed"