$srcDir = "D:\data\A-shares"
$bakDir = "D:\data\A-shares\.backup_20260607"
$pattern = ',(\d{6})\.sh,'
$replacement = ',sh.$1,'

if (-not (Test-Path $bakDir)) { New-Item -ItemType Directory -Path $bakDir | Out-Null }

$files = Get-ChildItem -LiteralPath $srcDir -Filter "*.csv" | Where-Object { $_.Name -notlike '.backup_*' }

$patched = 0
$skipped = 0
$errors = 0
$utf8NoBom = New-Object System.Text.UTF8Encoding($False)

foreach ($f in $files) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)

        if ($text -notmatch $pattern) {
            $skipped++
            continue
        }

        $bakPath = Join-Path $bakDir $f.Name
        [System.IO.File]::WriteAllBytes($bakPath, $bytes)

        $newText = $text -replace $pattern, $replacement

        $tmpPath = "$($f.FullName).tmp"
        [System.IO.File]::WriteAllText($tmpPath, $newText, $utf8NoBom)
        Move-Item -LiteralPath $tmpPath -Destination $f.FullName -Force

        $patched++
    } catch {
        Write-Warning "FAIL: $($f.Name) - $($_.Exception.Message)"
        $errors++
    }
}

Write-Host "Patched: $patched"
Write-Host "Skipped: $skipped"
Write-Host "Errors: $errors"
Write-Host "Backup: $bakDir"