$ErrorActionPreference = 'Stop'

$script:AssertionCount = 0

function Assert-Equal {
    param(
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Actual,
        [Parameter(Mandatory)][string]$Message
    )

    $script:AssertionCount++
    if ($Expected -cne $Actual) {
        throw "$Message. Expected: [$Expected] Actual: [$Actual]"
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    $script:AssertionCount++
    if (-not $Condition) { throw $Message }
}

function Get-Lines {
    param([Parameter(Mandatory)][string]$Path)

    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $lines = @($content -split "`n")
    if ($lines.Count -gt 0 -and $lines[-1] -eq '') {
        $lines = $lines[0..($lines.Count - 2)]
    }
    return @($lines | ForEach-Object { $_.TrimEnd("`r") })
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$converter = Join-Path $repoRoot 'convert_kline.ps1'
$fixtureDir = Join-Path $PSScriptRoot 'fixtures'
$timeFixture = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'wind-time-reordered.json'), [System.Text.Encoding]::UTF8)
$legacyFixture = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'wind-legacy-date.json'), [System.Text.Encoding]::UTF8)
$singleRowFixture = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'wind-single-row-time.json'), [System.Text.Encoding]::UTF8)
$emptyRowsFixture = [System.IO.File]::ReadAllText((Join-Path $fixtureDir 'wind-empty-rows.json'), [System.Text.Encoding]::UTF8)
$header = 'date,code,open,high,low,close,volume,turnover,changehandrate,avprice'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("a-share-kline-puller-convert-tests-" + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null

try {
    $samples = @(
        [PSCustomObject]@{ Name = 'stock'; Exchange = 'sh'; Code = '600000' },
        [PSCustomObject]@{ Name = 'etf'; Exchange = 'sh'; Code = '510300' },
        [PSCustomObject]@{ Name = 'wind-index'; Exchange = 'sh'; Code = '000001' }
    )

    foreach ($sample in $samples) {
        $outputPath = Join-Path $tempRoot ($sample.Name + '.csv')
        & $converter -JsonText $timeFixture -Exchange $sample.Exchange -Code $sample.Code -OutputPath $outputPath | Out-Null
        $lines = Get-Lines -Path $outputPath
        Assert-Equal -Expected $header -Actual $lines[0] -Message "$($sample.Name) header has all ten fields"
        Assert-Equal -Expected '4' -Actual ([string]$lines.Count) -Message "$($sample.Name) preserves all three data rows"
        Assert-Equal -Expected "$($sample.Exchange).$($sample.Code)" -Actual (($lines[1].Split(','))[1]) -Message "$($sample.Name) code is retained"
        foreach ($line in $lines) {
            Assert-Equal -Expected '10' -Actual ([string]$line.Split(',').Count) -Message "$($sample.Name) line has ten columns"
        }
        if ($sample.Name -eq 'stock') { $stockLines = $lines; $stockPath = $outputPath }
    }

    Assert-Equal -Expected '2024/6/5,sh.600000,10.00,10.50,9.80,10.20,1000,123456789.12,1.23,10.25' -Actual $stockLines[1] -Message 'TIME response maps all fields by name'
    Assert-Equal -Expected '2024/6/3,sh.600000,9.90,10.30,9.70,10.10,,,,' -Actual $stockLines[2] -Message 'null metric values remain empty'
    Assert-Equal -Expected '2024/6/4,sh.600000,10.10,10.60,10.00,10.40,2345.67,210000.55,2.3456,10.42' -Actual $stockLines[3] -Message 'Wind response order and raw values are retained'

    $bytes = [System.IO.File]::ReadAllBytes($stockPath)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Assert-True -Condition (-not $hasBom) -Message 'CSV is UTF-8 without BOM'

    $singleRowPath = Join-Path $tempRoot 'single-row.csv'
    & $converter -JsonText $singleRowFixture -Exchange 'sz' -Code '300001' -OutputPath $singleRowPath | Out-Null
    $singleRowLines = Get-Lines -Path $singleRowPath
    Assert-Equal -Expected $header -Actual $singleRowLines[0] -Message 'single-row response has all ten fields'
    Assert-Equal -Expected '2' -Actual ([string]$singleRowLines.Count) -Message 'single-row response remains one data row'
    Assert-Equal -Expected '2024/6/3,sz.300001,9.90,10.30,9.70,10.10,1000,1234.56,1.23,10.25' -Actual $singleRowLines[1] -Message 'single TIME row is converted'

    $legacyPath = Join-Path $tempRoot 'legacy.csv'
    & $converter -JsonText $legacyFixture -Exchange 'sz' -Code '159001' -OutputPath $legacyPath | Out-Null
    $legacyLines = Get-Lines -Path $legacyPath
    Assert-Equal -Expected $header -Actual $legacyLines[0] -Message 'legacy _DATE header has all ten fields'
    Assert-Equal -Expected '2024/6/4,sz.159001,8.60,9.00,8.50,8.80,50,438.20,0.50,8.75' -Actual $legacyLines[1] -Message 'legacy response order is retained'
    Assert-Equal -Expected '2024/6/3,sz.159001,8.00,8.30,7.90,8.10,40,320.00,0.40,8.05' -Actual $legacyLines[2] -Message 'legacy second row retains all fields'

    $emptyRowsPath = Join-Path $tempRoot 'empty-rows.csv'
    [System.IO.File]::WriteAllText($emptyRowsPath, "existing-history`n", (New-Object System.Text.UTF8Encoding($false)))
    & $converter -JsonText $emptyRowsFixture -Exchange 'sh' -Code '600002' -OutputPath $emptyRowsPath | Out-Null
    $emptyRowsLines = Get-Lines -Path $emptyRowsPath
    Assert-Equal -Expected '1' -Actual ([string]$emptyRowsLines.Count) -Message 'empty rows retain the original zero-row CSV behavior'
    Assert-Equal -Expected $header -Actual ([string]$emptyRowsLines) -Message 'empty rows produce a header-only CSV for no_data_candidate review'
    Assert-True -Condition (-not [System.IO.File]::Exists($emptyRowsPath + '.tmp')) -Message 'empty rows leave no temporary CSV'

    Write-Host "PASS: $script:AssertionCount assertions"
} finally {
    if ([System.IO.Directory]::Exists($tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
