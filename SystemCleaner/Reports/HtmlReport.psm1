Set-StrictMode -Version Latest

function New-UscCsvReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Results,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [Parameter(Mandatory)][string]$RunId
    )

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $outputPath = Join-Path $OutputDirectory "UltimateSystemCleaner-$RunId.csv"
    $rows = foreach ($result in @($Results)) {
        [pscustomobject]@{
            RunId       = $RunId
            Name        = $result.Name
            Category    = $result.Category
            Status      = $result.Status
            BytesBefore = $result.BytesBefore
            BytesAfter  = $result.BytesAfter
            BytesFreed  = $result.BytesFreed
            Message     = $result.Message
            Timestamp   = $result.Timestamp
        }
    }

    $rows | Export-Csv -LiteralPath $outputPath -NoTypeInformation -Encoding UTF8
    return $outputPath
}

function Format-UscHtmlEncode {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return [System.Security.SecurityElement]::Escape($Text)
}

function Format-UscReportBytes {
    param([Int64]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function New-UscHtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Run,
        [Parameter(Mandatory)][string]$OutputDirectory
    )

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $outputPath = Join-Path $OutputDirectory "UltimateSystemCleaner-$($Run.RunId).html"
    $duration = if ($Run.Started -and $Run.Finished) {
        ($Run.Finished - $Run.Started).ToString('mm\:ss')
    } else { '—' }

    $dryRunBanner = if ($Run.WhatIfOnly) {
        '<div class="banner dry-run">DRY RUN - no files were deleted. Toggle DryRunDefault in settings to run for real.</div>'
    } else { '' }

    $driveRows = ''
    foreach ($before in @($Run.Before)) {
        $after = @($Run.After) | Where-Object { $_.Drive -eq $before.Drive } | Select-Object -First 1
        $afterFree = if ($after) { [Int64]$after.FreeSpace } else { [Int64]$before.FreeSpace }
        $delta = $afterFree - [Int64]$before.FreeSpace
        $deltaClass = if ($delta -gt 0) { 'good' } elseif ($delta -lt 0) { 'bad' } else { 'neutral' }
        $deltaText = if ($delta -gt 0) { "+$(Format-UscReportBytes -Bytes $delta)" } elseif ($delta -lt 0) { Format-UscReportBytes -Bytes $delta } else { 'unchanged' }
        $driveRows += @"
<tr>
  <td>$($before.Drive)</td>
  <td>$(Format-UscReportBytes -Bytes $before.FreeSpace)</td>
  <td>$(Format-UscReportBytes -Bytes $afterFree)</td>
  <td class="$deltaClass">$deltaText</td>
</tr>
"@
    }

    $opRows = ''
    foreach ($op in @($Run.Results)) {
        $statusClass = switch ($op.Status) {
            'Succeeded' { 'good' }
            'PartiallySucceeded' { 'warn' }
            'Simulated' { 'sim' }
            'Failed' { 'bad' }
            default { 'neutral' }
        }
        $opRows += @"
<tr>
  <td>$(Format-UscHtmlEncode -Text $op.Name)</td>
  <td class="$statusClass">$($op.Status)</td>
  <td>$(Format-UscReportBytes -Bytes $op.BytesFreed)</td>
  <td>$(Format-UscHtmlEncode -Text $op.Message)</td>
</tr>
"@
    }

    $totalLabel = if ($Run.WhatIfOnly) { 'Estimated Reclaimable' } else { 'Total Freed' }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>Ultimate System Cleaner - $($Run.RunId)</title>
  <style>
    body { font-family: Segoe UI, sans-serif; background: #0f1419; color: #e6edf3; margin: 0; padding: 24px; }
    h1 { color: #58a6ff; margin-bottom: 4px; }
    .meta { color: #8b949e; margin-bottom: 20px; }
    .banner { padding: 12px 16px; border-radius: 8px; margin-bottom: 20px; font-weight: 600; }
    .dry-run { background: #3d2e00; color: #f0c14b; border: 1px solid #f0c14b; }
    table { width: 100%; border-collapse: collapse; margin-bottom: 24px; }
    th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid #30363d; }
    th { background: #161b22; color: #58a6ff; }
    .good { color: #3fb950; }
    .warn { color: #d29922; }
    .bad { color: #f85149; }
    .sim { color: #a371f7; }
    .neutral { color: #8b949e; }
    .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 16px; margin-bottom: 20px; }
    .stat { font-size: 1.4em; color: #3fb950; }
  </style>
</head>
<body>
  <h1>Ultimate System Cleaner Report</h1>
  <p class="meta">Run $($Run.RunId) · Mode: $($Run.Mode) · Duration: $duration · Admin: $($Run.IsAdministrator)</p>
  $dryRunBanner
  <div class="card">
    <div>$totalLabel</div>
    <div class="stat">$(Format-UscReportBytes -Bytes $Run.TotalBytesFreed)</div>
  </div>
  <h2>Disk Space</h2>
  <table>
    <tr><th>Drive</th><th>Before (free)</th><th>After (free)</th><th>Change</th></tr>
    $driveRows
  </table>
  <h2>Operations</h2>
  <table>
    <tr><th>Task</th><th>Status</th><th>Size</th><th>Details</th></tr>
    $opRows
  </table>
</body>
</html>
"@

    $html | Set-Content -LiteralPath $outputPath -Encoding UTF8
    return $outputPath
}

Export-ModuleMember -Function New-UscHtmlReport, New-UscCsvReport, Format-UscReportBytes
