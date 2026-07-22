$ErrorActionPreference = 'Stop'
$lines = Get-Content "C:\Users\Edward\Documents\i2c_capture.csv"

# Pass 1: Intel-iaLPSS2-I2C 1091 events -> address + direction + seq + clock, all via regex
$addrList = New-Object System.Collections.Generic.List[object]
foreach ($l in $lines) {
    if ($l -like 'Intel-iaLPSS2-I2C *Info*1091*') {
        if ($l -match '(0x[0-9A-Fa-f]+)\s*,\s*0\s*,\s*1\s*,\s*"(WRITE|READ)\s*"\s*,\s*"Sequence\s*"\s*,\s*(\d+)') {
            $addr = $matches[1]; $dir = $matches[2]; $seq = [int]$matches[3]
            if ($l -match ',\s*(\d{15,20})\s*,\s*-?\d+\s*,\s*-?\d+\s*,\s*' + [regex]::Escape($addr)) {
                $clock = [int64]$matches[1]
                $addrList.Add([pscustomobject]@{ Clock=$clock; Addr=$addr; Dir=$dir; Seq=$seq })
            }
        }
    }
}
Write-Host "Address events parsed: $($addrList.Count)"

# Pass 2: SPB-ClassExtension events, group by Activity ID via regex (the {guid} field)
$txByActivity = @{}
foreach ($l in $lines) {
    if ($l -like 'Microsoft-Windows-SPB-ClassExtension *') {
        if ($l -notmatch '(\{[0-9a-fA-F-]{36}\})') { continue }
        $activity = $matches[1]
        if ($l -notmatch ',\s*(\d{15,20})\s*,\s*-?\d+\s*,\s*-?\d+\s*,') { continue }
        $clock = [int64]$matches[1]
        $eventName = ($l -split ',')[1].Trim()

        if (-not $txByActivity.ContainsKey($activity)) {
            $txByActivity[$activity] = [pscustomobject]@{
                Activity=$activity; StartClock=$null; Bytes=(New-Object System.Collections.Generic.List[string]); Direction=$null
            }
        }
        $tx = $txByActivity[$activity]
        if ($eventName -eq 'Start' -and $tx.StartClock -eq $null) { $tx.StartClock = $clock }
        elseif ($eventName -eq 'IoSpbPayloadTdBuffer') {
            if ($l -match '0x[0-9A-Fa-f]+\s*$') {
                $hexField = $matches[0].Trim()
                $tx.Bytes.Add($hexField)
            }
        }
        elseif ($eventName -eq 'IoSpbPayloadTdStart') {
            if ($l -match '"(FromDevice|ToDevice)\s*"') { $tx.Direction = $matches[1] }
        }
    }
}
Write-Host "SPB transactions parsed: $($txByActivity.Count)"

$txArr = @($txByActivity.Values | Where-Object { $_.StartClock -ne $null } | Sort-Object StartClock)
Write-Host "SPB transactions with StartClock: $($txArr.Count)"

# Merge: for each address event (in order), find nearest SPB transaction by start clock
$results = New-Object System.Collections.Generic.List[object]
foreach ($ae in ($addrList | Sort-Object Clock)) {
    $best = $null; $bestDiff = [int64]::MaxValue
    foreach ($tx in $txArr) {
        $diff = [Math]::Abs($tx.StartClock - $ae.Clock)
        if ($diff -lt $bestDiff) { $bestDiff = $diff; $best = $tx }
    }
    $bytesFinal = if ($best -and $best.Bytes.Count -gt 0) { $best.Bytes[$best.Bytes.Count-1] } else { $null }
    $results.Add([pscustomobject]@{
        Clock=$ae.Clock; Addr=$ae.Addr; Dir=$ae.Dir; Seq=$ae.Seq; Bytes=$bytesFinal; TxDir=($best.Direction); TimeDiffTicks=$bestDiff
    })
}

$results | Sort-Object Clock | Export-Csv "C:\Users\Edward\Documents\i2c_reconstructed.csv" -NoTypeInformation
Write-Host "Wrote i2c_reconstructed.csv with $($results.Count) rows"
