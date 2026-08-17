param(
    [Parameter(Mandatory)][string]$JsonText,
    [Parameter(Mandatory)][string]$Exchange,
    [Parameter(Mandatory)][string]$Code,
    [Parameter(Mandatory)][string]$OutputPath
)

if ($JsonText.Length -gt 0 -and $JsonText[0] -eq [char]0xFEFF) {
    $JsonText = $JsonText.Substring(1)
}

$outer = $JsonText | ConvertFrom-Json
$inner = $outer.content[0].text | ConvertFrom-Json

$cols = @($inner.data.columns | ForEach-Object { $_.name })
$dateField = if ($cols.IndexOf('_DATE') -ge 0) { '_DATE' } else { 'TIME' }
$idx = @{
    date = $cols.IndexOf($dateField)
    open = $cols.IndexOf('OPEN')
    high = $cols.IndexOf('HIGH')
    low = $cols.IndexOf('LOW')
    close = $cols.IndexOf('MATCH')
    volume = $cols.IndexOf('VOLUME')
    turnover = $cols.IndexOf('TURNOVER')
    changehandrate = $cols.IndexOf('CHANGEHANDRATE')
    avprice = $cols.IndexOf('AVPRICE')
}

$codeFmt = "$Exchange.$Code"
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("date,code,open,high,low,close,volume,turnover,changehandrate,avprice")

if ($inner.data.rows) {
    foreach ($row in $inner.data.rows) {
        $raw = $row[$idx.date]
        if ($dateField -eq '_DATE') {
            $y = $raw.Substring(0,4)
            $m = [int]$raw.Substring(4,2)
            $d = [int]$raw.Substring(6,2)
            $dateFmt = "$y/$m/$d"
        } else {
            $date = [datetimeoffset]::Parse([string]$raw).Date
            $dateFmt = "$($date.Year)/$($date.Month)/$($date.Day)"
        }
        $line = "$dateFmt,$codeFmt,$($row[$idx.open]),$($row[$idx.high]),$($row[$idx.low]),$($row[$idx.close]),$($row[$idx.volume]),$($row[$idx.turnover]),$($row[$idx.changehandrate]),$($row[$idx.avprice])"
        [void]$sb.AppendLine($line)
    }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($False)
$tmp = "$OutputPath.tmp"
[System.IO.File]::WriteAllText($tmp, $sb.ToString(), $utf8NoBom)
Move-Item $tmp $OutputPath -Force

$rows = if ($inner.data.rows) { $inner.data.rows.Count } else { 0 }
Write-Host "OK: $OutputPath rows=$rows"
