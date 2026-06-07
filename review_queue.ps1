param(
    [string]$ProgressFile = "D:\data\拉取进度.json",
    [string]$OutputFile = "D:\data\拉取进度.review_queue.json"
)

if (-not [System.IO.File]::Exists($ProgressFile)) { throw "Progress file not found: $ProgressFile" }

$content = [System.IO.File]::ReadAllText($ProgressFile, [System.Text.Encoding]::UTF8)
$p = $content | ConvertFrom-Json
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$review = [ordered]@{}
$count = 0
foreach ($prop in $p.stocks.PSObject.Properties) {
    $e = $prop.Value
    if ($e.PSObject.Properties.Name -notcontains 'needsManualReview') { continue }
    if ($e.needsManualReview -ne $true) { continue }
    $symbol = $prop.Name
    $review[$symbol] = [ordered]@{
        category         = $e.category
        rows             = $e.rows
        firstDate        = $e.firstDate
        historyStatus    = $e.historyStatus
        needsManualReview = $true
        addedAt          = $now
    }
    $count++
}

$out = [ordered]@{
    lastUpdatedAt = $now
    pendingReview = $review
}

$json = $out | ConvertTo-Json -Depth 10
$utf8NoBom = New-Object System.Text.UTF8Encoding($False)
$tmp = "$OutputFile.tmp"
[System.IO.File]::WriteAllText($tmp, $json, $utf8NoBom)
Move-Item $tmp $OutputFile -Force

Write-Host "✅ Review queue dumped: $count entries → $OutputFile"