Set-StrictMode -Version Latest

# Shared hash table to track operations timing
$script:ProgressTracker = @{}

function Start-UscProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Activity,
        [string]$Status = 'Starting',
        [int]$Id = 1,
        [int]$ParentId = -1
    )
    
    $script:ProgressTracker[$Id] = @{
        Activity = $Activity
        StartTime = Get-Date
    }

    Write-Progress -Id $Id -ParentId $ParentId -Activity $Activity -Status $Status -PercentComplete 0
}

function Update-UscProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Activity,
        [string]$Status = '',
        [int]$PercentComplete = 0,
        [int]$Id = 1,
        [int]$ParentId = -1
    )
    
    $bounded = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
    
    # Calculate ETA if start time is known
    $etaString = ''
    if ($script:ProgressTracker.Contains($Id) -and $bounded -gt 0) {
        $elapsed = (Get-Date) - $script:ProgressTracker[$Id].StartTime
        $totalEstimatedMs = ($elapsed.TotalMilliseconds / $bounded) * 100
        $remainingMs = $totalEstimatedMs - $elapsed.TotalMilliseconds
        if ($remainingMs -gt 0) {
            $remaining = [TimeSpan]::FromMilliseconds($remainingMs)
            $etaString = ' [Est. Remaining: {0:mm\:ss}]' -f $remaining
        }
    }

    $displayStatus = $Status
    if ($etaString) {
        $displayStatus = "$Status$etaString"
    }

    # Render standard progress bar
    Write-Progress -Id $Id -ParentId $ParentId -Activity $Activity -Status $displayStatus -PercentComplete $bounded

    # Render our custom flapping falkon mascot
    Update-UscConsoleProgress -Activity $Activity -Status $Status -PercentComplete $bounded
}

function Complete-UscProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Activity,
        [int]$Id = 1,
        [int]$ParentId = -1
    )
    if ($script:ProgressTracker.Contains($Id)) {
        $null = $script:ProgressTracker.Remove($Id)
    }
    Write-Progress -Id $Id -ParentId $ParentId -Activity $Activity -Completed

    # Clear custom progress line from the console
    if ([Environment]::UserInteractive) {
        Write-Host ("`r" + (' ' * 110) + "`r") -NoNewline
    }
}

function Format-UscBytes {
    [CmdletBinding()]
    param([Int64]$Bytes)

    if ($Bytes -ge 1TB) { return '{0:N2} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# A simple console text spinner for visual feedback in scripts
$script:SpinnerIndex = 0
$script:SpinnerFrames = @('|', '/', '-', '\')

function Get-UscSpinner {
    $frame = $script:SpinnerFrames[$script:SpinnerIndex]
    $script:SpinnerIndex = ($script:SpinnerIndex + 1) % $script:SpinnerFrames.Count
    return $frame
}

$script:FalkonFrameIndex = 0
$script:FalkonFrames = @(
    ' \_("v")_/ ',
    ' -_("o")_- ',
    ' /_("v")_\ ',
    ' -_("o")_- '
)

function Update-UscConsoleProgress {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete
    )
    if (-not [Environment]::UserInteractive) { return }

    $frame = $script:FalkonFrames[$script:FalkonFrameIndex]
    $script:FalkonFrameIndex = ($script:FalkonFrameIndex + 1) % $script:FalkonFrames.Count
    
    $progressBarWidth = 20
    $completedBlocks = [Math]::Max(0, [Math]::Min($progressBarWidth, [int]($PercentComplete / (100 / $progressBarWidth))))
    $remainingBlocks = $progressBarWidth - $completedBlocks
    $bar = ('#' * $completedBlocks) + ('.' * $remainingBlocks)
    
    $cleanMessage = '{0}: {1}' -f $Activity, $Status
    if ($cleanMessage.Length -gt 50) {
        $cleanMessage = $cleanMessage.Substring(0, 47) + '...'
    }
    
    $line = "`r  $frame  [$bar] $PercentComplete% | $cleanMessage"
    $padLength = 110 - $line.Length
    if ($padLength -gt 0) {
        $line += ' ' * $padLength
    }
    Write-Host $line -NoNewline -ForegroundColor Cyan
}

Export-ModuleMember -Function Start-UscProgress, Update-UscProgress, Complete-UscProgress, Format-UscBytes, Get-UscSpinner, Update-UscConsoleProgress

