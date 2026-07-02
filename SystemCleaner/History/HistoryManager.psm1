Set-StrictMode -Version Latest

$script:HistoryDir = Join-Path $env:ProgramData 'UltimateSystemCleaner\History'
$script:MaxHistoryRuns = 10

function Get-UscHistoryDirectory {
    if (-not (Test-Path $script:HistoryDir)) {
        New-Item -ItemType Directory -Path $script:HistoryDir -Force | Out-Null
    }
    return $script:HistoryDir
}

function Save-UscRunHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Run
    )

    $dir = Get-UscHistoryDirectory

    # Always coerce to arrays so .Count works on PowerShell 5 scalars
    $results    = @($Run.Results)
    $drivesBefore = @($Run.Before)
    $drivesAfter  = @($Run.After)

    $summary = [pscustomobject]@{
        RunId         = $Run.RunId
        Mode          = $Run.Mode
        Started       = $Run.Started.ToString('o')
        Finished      = $Run.Finished.ToString('o')
        ComputerName  = $Run.ComputerName
        WhatIfOnly    = $Run.WhatIfOnly
        TotalBytesFreed = [Int64]$Run.TotalBytesFreed
        DrivesBefore  = @($drivesBefore | ForEach-Object { [pscustomobject]@{ Drive = $_.Drive; FreeSpace = $_.FreeSpace; Size = $_.Size } })
        DrivesAfter   = @($drivesAfter  | ForEach-Object { [pscustomobject]@{ Drive = $_.Drive; FreeSpace = $_.FreeSpace; Size = $_.Size } })
        ResultsCount  = $results.Count
        SucceededOps  = @($results | Where-Object { $_.Status -eq 'Succeeded' }).Count
        FailedOps     = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
        SkippedOps    = @($results | Where-Object { $_.Status -in 'Skipped','Simulated' }).Count
    }

    $path = Join-Path $dir "run-$($Run.RunId).json"
    $summary | ConvertTo-Json -Depth 4 | Out-File -FilePath $path -Encoding UTF8 -Force

    # Prune old runs beyond the cap
    $allRuns = @(Get-ChildItem -LiteralPath $dir -Filter 'run-*.json' | Sort-Object CreationTime -Descending)
    if ($allRuns.Count -gt $script:MaxHistoryRuns) {
        $allRuns | Select-Object -Skip $script:MaxHistoryRuns | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Get-UscRunHistory {
    [CmdletBinding()]
    param(
        [int]$Count = $script:MaxHistoryRuns
    )

    $dir = Get-UscHistoryDirectory
    $files = @(Get-ChildItem -LiteralPath $dir -Filter 'run-*.json' -ErrorAction SilentlyContinue |
               Sort-Object CreationTime -Descending | Select-Object -First $Count)

    $runs = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        try {
            $raw = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
            $runs.Add(($raw | ConvertFrom-Json))
        } catch {
            # Skip malformed history files silently
        }
    }
    return @($runs)
}

function Show-UscRunHistory {
    [CmdletBinding()]
    param()

    $runs = @(Get-UscRunHistory)
    if ($runs.Count -eq 0) {
        Write-Host "  No history runs found." -ForegroundColor DarkGray
        return
    }

    Write-Host ""
    Write-Host "  RUN HISTORY (Last $($runs.Count) runs)" -ForegroundColor Cyan
    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("  {0,-22} {1,-12} {2,-10} {3,-12} {4}" -f "Run ID", "Mode", "WhatIf", "Freed", "Status") -ForegroundColor DarkGray

    foreach ($run in $runs) {
        $freed = if ($run.TotalBytesFreed -ge 1GB)      { "{0:N2} GB" -f ($run.TotalBytesFreed / 1GB) }
                 elseif ($run.TotalBytesFreed -ge 1MB)  { "{0:N2} MB" -f ($run.TotalBytesFreed / 1MB) }
                 elseif ($run.TotalBytesFreed -ge 1KB)  { "{0:N2} KB" -f ($run.TotalBytesFreed / 1KB) }
                 else                                   { "$($run.TotalBytesFreed) B" }

        $dryTag = if ($run.WhatIfOnly) { "Yes" } else { "No" }
        $statusTag = "[OK:$($run.SucceededOps) F:$($run.FailedOps) S:$($run.SkippedOps)]"

        $color = if ($run.FailedOps -gt 0) { 'Yellow' } else { 'Green' }
        Write-Host ("  {0,-22} {1,-12} {2,-10} {3,-12} {4}" -f $run.RunId, $run.Mode, $dryTag, $freed, $statusTag) -ForegroundColor $color
    }
    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
}

function Compare-UscLastTwoRuns {
    [CmdletBinding()]
    param()

    $runs = @(Get-UscRunHistory -Count 2)
    if ($runs.Count -lt 2) {
        Write-Host "  Not enough history for comparison (need at least 2 runs)." -ForegroundColor Yellow
        return
    }

    $current = $runs[0]
    $previous = $runs[1]

    Write-Host ""
    Write-Host "  COMPARISON: Latest vs Previous Run" -ForegroundColor Cyan
    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray

    $formatBytes = {
        param([Int64]$b)
        if ($b -ge 1GB) { "{0:N2} GB" -f ($b / 1GB) }
        elseif ($b -ge 1MB) { "{0:N2} MB" -f ($b / 1MB) }
        elseif ($b -ge 1KB) { "{0:N2} KB" -f ($b / 1KB) }
        else { "$b B" }
    }

    $prevFreed = & $formatBytes -b $previous.TotalBytesFreed
    $currFreed = & $formatBytes -b $current.TotalBytesFreed
    $delta     = $current.TotalBytesFreed - $previous.TotalBytesFreed
    $deltaStr  = "$(if ($delta -ge 0) { '+' })$(& $formatBytes -b ([Math]::Abs($delta)))"
    $deltaColor = if ($delta -gt 0) { 'Green' } elseif ($delta -lt 0) { 'Yellow' } else { 'Gray' }

    Write-Host ("  Previous Run [{0}] Mode: {1,-12}  Freed: {2}" -f $previous.RunId, $previous.Mode, $prevFreed) -ForegroundColor DarkGray
    Write-Host ("  Current Run  [{0}] Mode: {1,-12}  Freed: {2}" -f $current.RunId, $current.Mode, $currFreed) -ForegroundColor White
    Write-Host "  Change: $deltaStr" -ForegroundColor $deltaColor

    # Drive comparison
    foreach ($beforeDrive in $current.DrivesBefore) {
        $afterDrive = $current.DrivesAfter | Where-Object { $_.Drive -eq $beforeDrive.Drive }
        if ($afterDrive) {
            $reclaimed = $afterDrive.FreeSpace - $beforeDrive.FreeSpace
            $reclaimedStr = & $formatBytes -b ([Math]::Abs($reclaimed))
            Write-Host ("  Drive {0}  Free: Before {1} -> After {2} ({3} reclaimed)" -f `
                $beforeDrive.Drive,
                (& $formatBytes -b $beforeDrive.FreeSpace),
                (& $formatBytes -b $afterDrive.FreeSpace),
                $reclaimedStr) -ForegroundColor Cyan
        }
    }
    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
}

function Export-UscHistoryTrend {
    [CmdletBinding()]
    param(
        [string]$OutputPath = (Join-Path (Get-UscHistoryDirectory) 'trend.csv')
    )

    $runs = @(Get-UscRunHistory)
    if ($runs.Count -eq 0) {
        Write-Host "  No history available to export trend." -ForegroundColor Yellow
        return $null
    }

    $rows = foreach ($run in $runs) {
        [pscustomobject]@{
            RunId           = $run.RunId
            Mode            = $run.Mode
            Started         = $run.Started
            WhatIfOnly      = $run.WhatIfOnly
            TotalBytesFreed = $run.TotalBytesFreed
            SucceededOps    = $run.SucceededOps
            FailedOps       = $run.FailedOps
            SkippedOps      = $run.SkippedOps
        }
    }
    $rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Force
    return $OutputPath
}

Export-ModuleMember -Function Save-UscRunHistory, Get-UscRunHistory, Show-UscRunHistory, Compare-UscLastTwoRuns, Export-UscHistoryTrend
