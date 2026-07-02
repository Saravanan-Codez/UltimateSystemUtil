<# 
.SYNOPSIS
Ultimate System Cleaner - Enterprise Grade Windows Maintenance Utility
.DESCRIPTION
A highly structured, production-ready Windows cleanup and optimization suite.
Supports Safe, Aggressive, and Nuclear cleanup policies. Features runspace-based
multithreaded folder scanner, DISM side-by-side analytics, HTML dashboards,
scheduled task registration, and local code signing helpers.
.EXAMPLE
.\UltimateSystemCleaner.ps1 -Menu
.EXAMPLE
.\UltimateSystemCleaner.ps1 -Safe -GenerateReport
#>
[CmdletBinding(DefaultParameterSetName = 'Menu', SupportsShouldProcess)]
param(
    [Parameter(ParameterSetName = 'Safe')][switch]$Safe,
    [Parameter(ParameterSetName = 'Aggressive')][switch]$Aggressive,
    [Parameter(ParameterSetName = 'Nuclear')][switch]$Nuclear,
    [Parameter(ParameterSetName = 'Analyze')][switch]$Analyze,
    [Parameter(ParameterSetName = 'Diagnose')][switch]$Diagnose,
    [Parameter(ParameterSetName = 'ComponentStore')][switch]$ComponentStore,
    [Parameter(ParameterSetName = 'Schedule')][switch]$InstallScheduledTask,
    [Parameter(ParameterSetName = 'Schedule')][switch]$RemoveScheduledTask,
    [Parameter(ParameterSetName = 'Menu')][switch]$Menu,
    [switch]$GenerateReport,
    [switch]$WhatIfOnly,
    [switch]$ConfirmNuclear,
    [string]$ConfigPath
)

# --- Web Bootstrap Handler ---
if ([string]::IsNullOrEmpty($PSScriptRoot)) {
    $null = Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host '       FALKON SYSTEM CLEANER WEB BOOTSTRAP         ' -ForegroundColor White -BackgroundColor Blue
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host 'Running in web-load context. Bootstrapping files...' -ForegroundColor Gray
    
    $zipUrl = 'https://github.com/Saravanan-Codez/FalkonSysUtils/archive/refs/heads/main.zip'
    $tempDir = Join-Path $env:TEMP 'FalkonSysUtils-Bootstrap'
    
    try {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
        $zipFile = Join-Path $tempDir 'repo.zip'
        Write-Host 'Downloading repository package from GitHub...' -ForegroundColor Gray
        
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -Uri $zipUrl -OutFile $zipFile -ErrorAction Stop
        
        Write-Host 'Extracting files to temp workspace...' -ForegroundColor Gray
        Expand-Archive -Path $zipFile -DestinationPath $tempDir -Force -ErrorAction Stop
        
        $expandedFolder = Get-ChildItem -LiteralPath $tempDir -Directory | Select-Object -First 1
        if ($expandedFolder) {
            $launcherPath = Join-Path $expandedFolder.FullName 'SystemCleaner\UltimateSystemCleaner.ps1'
            Write-Host 'Running launcher in localized workspace...' -ForegroundColor Green
            Start-Sleep -Seconds 1
            
            $boundArgs = @{}
            foreach ($key in $PSBoundParameters.Keys) {
                $boundArgs[$key] = $PSBoundParameters[$key]
            }
            if ($boundArgs.Count -eq 0) {
                $boundArgs['Menu'] = $true
            }
            & $launcherPath @boundArgs
        }
        else {
            Write-Error 'Failed to locate extracted launcher files in temp directory.'
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Error "Web bootstrap failed: $errorMessage"
    }
    return
}

# Unblock downloaded script files to support manual ZIP downloads
Get-ChildItem -LiteralPath $PSScriptRoot -Include *.ps1,*.psm1 -Recurse -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePaths = @(
    'Core\Logger.psm1',
    'Core\Config.psm1',
    'Core\Progress.psm1',
    'Core\RunspaceManager.psm1',
    'Analysis\DiskAnalyzer.psm1',
    'Analysis\ComponentStoreAnalyzer.psm1',
    'Cleanup\TempCleaner.psm1',
    'Cleanup\CacheCleaner.psm1',
    'Cleanup\BrowserCleaner.psm1',
    'Cleanup\GPUCacheCleaner.psm1',
    'Cleanup\WindowsUpdateCleaner.psm1',
    'Cleanup\DumpCleaner.psm1',
    'Reports\JsonReport.psm1',
    'Reports\HtmlReport.psm1',
    'History\HistoryManager.psm1'
)

# Import all required modules
foreach ($module in $modulePaths) {
    $fullPath = Join-Path $PSScriptRoot $module
    Import-Module $fullPath -Force
}


function Test-UscAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-UscRestorePoint {
    [CmdletBinding()]
    param([string]$Description = 'Ultimate System Cleaner checkpoint')

    if (-not (Test-UscAdministrator)) {
        return New-UscOperationResult -Name 'Restore Point' -Category Checkpoint -Status Skipped -Message 'Administrator rights are required'
    }

    try {
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS'
        return New-UscOperationResult -Name 'Restore Point' -Category Checkpoint -Status Succeeded -Message $Description
    }
    catch {
        Write-UscLog -Level Warning -Message 'Restore point creation failed (usually happens if restore points are disabled or another is running)' -Exception $_.Exception
        return New-UscOperationResult -Name 'Restore Point' -Category Checkpoint -Status Failed -Message $_.Exception.Message
    }
}

function Register-UscScheduledTask {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ScriptPath)

    $taskName = 'UltimateSystemCleaner-SafeWeekly'
    if ($PSCmdlet.ShouldProcess($taskName, 'Register weekly safe cleanup task')) {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Safe -GenerateReport"
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Description 'Runs Ultimate System Cleaner in Safe mode weekly.' -Force | Out-Null
        return New-UscOperationResult -Name 'Scheduled Task' -Category Configure -Status Succeeded -Message $taskName
    }
}

function Unregister-UscScheduledTask {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $taskName = 'UltimateSystemCleaner-SafeWeekly'
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($taskName, 'Unregister scheduled task')) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            return New-UscOperationResult -Name 'Scheduled Task' -Category Configure -Status Succeeded -Message 'Removed'
        }
    }
    return New-UscOperationResult -Name 'Scheduled Task' -Category Configure -Status Skipped -Message 'Task was not installed'
}

function Invoke-UscAnalysis {
    [CmdletBinding()]
    param([psobject]$Config)

    Start-UscProgress -Activity 'Analyzing Disk Usage' -Status 'Retrieving drive snapshots...' -Id 1
    $drive = @(Get-UscDriveSnapshot)

    Update-UscProgress -Activity 'Analyzing Disk Usage' -Status 'Scanning for cleanup opportunities...' -PercentComplete 50 -Id 1
    $opportunities = @(Get-UscCleanupOpportunity -Config $Config)

    Complete-UscProgress -Activity 'Analyzing Disk Usage' -Id 1

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $opportunities) {
        $results.Add((New-UscOperationResult -Name "Opportunity: $($item.Path)" -Category Analyze -Status Succeeded -BytesBefore $item.Bytes -Message "$($item.Files) candidate files"))
    }
    foreach ($snapshot in $drive) {
        $results.Add((New-UscOperationResult -Name "Drive $($snapshot.Drive)" -Category Analyze -Status Succeeded -BytesBefore $snapshot.UsedSpace -BytesAfter $snapshot.FreeSpace -Message "$($snapshot.PercentFree)% free"))
    }
    return @($results)
}

function Invoke-UscCleanupMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Safe','Aggressive','Nuclear')][string]$Mode,
        [Parameter(Mandatory)][psobject]$Config,
        [switch]$WhatIfOnly,
        [switch]$ConfirmNuclear
    )

    $results = [System.Collections.Generic.List[object]]::new()
    Start-UscProgress -Activity "Ultimate System Cleaner: $Mode" -Status 'Preparing system cleaner...' -Id 1

    Write-Host ''
    Write-Host " Starting $Mode cleanup$(if ($WhatIfOnly) { ' (DRY RUN)' } else { '' })..." -ForegroundColor Cyan
    Write-Host '--------------------------------------------------' -ForegroundColor DarkGray

    if ($Config.CreateRestorePoint -and -not $WhatIfOnly) {
        Update-UscProgress -Activity "Ultimate System Cleaner: $Mode" -Status 'Creating System Restore Point...' -PercentComplete 5 -Id 1
        Add-UscCleanupResult -Results $results -Result (New-UscRestorePoint -Description "Ultimate System Cleaner $Mode mode") -WhatIfOnly:$WhatIfOnly
    }

    # Safe operations
    Update-UscProgress -Activity "Ultimate System Cleaner: $Mode" -Status 'Executing Safe Cleaners...' -PercentComplete 15 -Id 1
    if ($Config.Safe.Temp) { 
        Start-UscProgress -Activity 'Cleaning Temp Folders' -Status 'Processing User/System temporary items...' -Id 2 -ParentId 1
        Add-UscCleanupResults -Results $results -NewResults @(Invoke-UscTempCleanup -Config $Config -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
        Complete-UscProgress -Activity 'Cleaning Temp Folders' -Id 2
    }
    if ($Config.Safe.RecycleBin) { 
        Add-UscCleanupResult -Results $results -Result (Invoke-UscRecycleBinCleanup -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
    }
    if ($Config.Safe.BrowserCache) {
        Start-UscProgress -Activity 'Cleaning Browser Cache' -Status 'Scanning chromium and gecko profiles...' -Id 3 -ParentId 1
        Add-UscCleanupResults -Results $results -NewResults @(Invoke-UscBrowserCacheCleanup -Config $Config -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
        Complete-UscProgress -Activity 'Cleaning Browser Cache' -Id 3
    }

    # Aggressive operations
    if ($Mode -in 'Aggressive','Nuclear') {
        Update-UscProgress -Activity "Ultimate System Cleaner: $Mode" -Status 'Executing Aggressive Cleaners...' -PercentComplete 40 -Id 1
        
        if ($Config.Aggressive.WindowsErrorReporting) { 
            Add-UscCleanupResults -Results $results -NewResults @(Invoke-UscWerCleanup -Config $Config -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
        }
        if ($Config.Aggressive.GpuShaderCache) { 
            Add-UscCleanupResults -Results $results -NewResults @(Invoke-UscGpuCacheCleanup -Config $Config -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
        }
        if ($Config.Aggressive.BrowserCache -and -not $Config.Safe.BrowserCache) { 
            Start-UscProgress -Activity 'Cleaning Browser Cache' -Status 'Scanning chromium and gecko profiles...' -Id 3 -ParentId 1
            Add-UscCleanupResults -Results $results -NewResults @(Invoke-UscBrowserCacheCleanup -Config $Config -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
            Complete-UscProgress -Activity 'Cleaning Browser Cache' -Id 3
        }
        if ($Config.Aggressive.WindowsUpdateCache) { 
            Add-UscCleanupResult -Results $results -Result (Invoke-UscWindowsUpdateCleanup -Config $Config -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
        }
        if ($Config.EnableStorageSenseIntegration) { 
            Add-UscCleanupResult -Results $results -Result (Invoke-UscStorageSense -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
        }
        if ($Config.Aggressive.DnsFlush) {
            Add-UscCleanupResult -Results $results -Result (Invoke-UscDnsFlush -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
        }
        if ($Config.Aggressive.FontCache) {
            Add-UscCleanupResult -Results $results -Result (Invoke-UscFontCacheCleanup -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
        }
        if ($Config.Aggressive.DeliveryOptimization) {
            Add-UscCleanupResult -Results $results -Result (Invoke-UscDeliveryOptimizationCleanup -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
        }
    }

    # Nuclear operations
    if ($Mode -eq 'Nuclear') {
        Update-UscProgress -Activity "Ultimate System Cleaner: $Mode" -Status 'Executing Nuclear Cleaners...' -PercentComplete 75 -Id 1
        if (-not $ConfirmNuclear -and $Config.ConfirmNuclearActions) {
            Add-UscCleanupResult -Results $results -Result (New-UscOperationResult -Name 'Nuclear Mode' -Category Clean -Status Skipped -Message 'Skipped destructive operations. Re-run with -ConfirmNuclear to unlock configured nuclear tasks.') -WhatIfOnly:$WhatIfOnly
        }
        else {
            if ($Config.Nuclear.CrashDumps) { 
                Add-UscCleanupResults -Results $results -NewResults @(Invoke-UscDumpCleanup -Config $Config -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
            }
            Add-UscCleanupResult -Results $results -Result (Invoke-UscComponentStoreCleanup -ResetBase:([bool]$Config.Nuclear.ComponentStoreResetBase) -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
            Add-UscCleanupResults -Results $results -NewResults @(Invoke-UscNuclearRecoveryCleanup -Config $Config -Confirmed:$ConfirmNuclear -WhatIfOnly:$WhatIfOnly) -WhatIfOnly:$WhatIfOnly
        }
    }

    Update-UscProgress -Activity "Ultimate System Cleaner: $Mode" -Status 'Wrapping up run...' -PercentComplete 95 -Id 1
    Complete-UscProgress -Activity "Ultimate System Cleaner: $Mode" -Id 1
    return @($results)
}

function New-UscRunRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][object[]]$Results,
        [Parameter(Mandatory)][psobject]$Config,
        [switch]$WhatIfOnly
    )

    $total = Measure-UscObjectSum -InputObject $Results -Property BytesFreed
    [pscustomobject]@{
        RunId = $RunId
        Mode = $Mode
        Started = $script:Started
        Finished = Get-Date
        ComputerName = $env:COMPUTERNAME
        UserName = [Environment]::UserName
        IsAdministrator = Test-UscAdministrator
        WhatIfOnly = [bool]$WhatIfOnly
        TotalBytesFreed = [Int64]$total
        Before = $script:BeforeSnapshot
        After = @(Get-UscDriveSnapshot)
        Results = @($Results)
        Audit = @(Get-UscAuditTrail)
        Config = $Config
    }
}

function Add-UscCleanupResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Results,
        [Parameter(Mandatory)][object]$Result,
        [switch]$WhatIfOnly
    )
    $Results.Add($Result)
    Write-UscOperationConsole -Result $Result -WhatIfOnly:$WhatIfOnly
}

function Add-UscCleanupResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Results,
        [Parameter(Mandatory)][object[]]$NewResults,
        [switch]$WhatIfOnly
    )
    foreach ($result in @($NewResults)) {
        Add-UscCleanupResult -Results $Results -Result $result -WhatIfOnly:$WhatIfOnly
    }
}

function Show-UscResultsSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Run,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$LogFile,
        [string[]]$ReportPaths = @()
    )

    $duration = if ($Run.Started -and $Run.Finished) {
        ($Run.Finished - $Run.Started).ToString('mm\:ss')
    } else { '-' }

    $isAnalyzeMode = $Run.Mode -in 'Diagnose', 'Analyze', 'DeepSpace', 'ComponentStore'

    Write-Host ''
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host '       ULTIMATE SYSTEM CLEANER - RESULTS          ' -ForegroundColor White -BackgroundColor Blue
    Write-Host '==================================================' -ForegroundColor Cyan

    if ($Run.WhatIfOnly -and -not $isAnalyzeMode) {
        Write-Host '  *** DRY RUN - nothing was deleted ***' -ForegroundColor Yellow
        Write-Host '  Toggle DryRunDefault in Settings, or confirm when prompted.' -ForegroundColor Gray
        Write-Host '--------------------------------------------------' -ForegroundColor Cyan
    }

    Write-Host " Run ID         : $RunId"
    Write-Host " Mode           : $($Run.Mode)"
    Write-Host " Duration       : $duration"
    Write-Host " Admin          : $($Run.IsAdministrator)"

    if (-not $isAnalyzeMode) {
        Write-Host '--------------------------------------------------' -ForegroundColor Cyan
        Write-Host ' DISK SPACE' -ForegroundColor Green
        foreach ($before in @($Run.Before)) {
            $after = @($Run.After) | Where-Object { $_.Drive -eq $before.Drive } | Select-Object -First 1
            $afterFree = if ($after) { [Int64]$after.FreeSpace } else { [Int64]$before.FreeSpace }
            $delta = $afterFree - [Int64]$before.FreeSpace
            $deltaText = if ($delta -gt 0) { "+$(Format-UscBytes -Bytes $delta)" } elseif ($delta -lt 0) { "-$(Format-UscBytes -Bytes ([Math]::Abs($delta)))" } else { 'unchanged' }
            $deltaColor = if ($delta -gt 0) { 'Green' } elseif ($delta -lt 0) { 'Red' } else { 'DarkGray' }
            Write-Host "  Drive $($before.Drive):"
            Write-Host "    Before : $(Format-UscBytes -Bytes $before.FreeSpace) free" -ForegroundColor Gray
            Write-Host "    After  : $(Format-UscBytes -Bytes $afterFree) free" -ForegroundColor Gray
            Write-Host "    Change : $deltaText" -ForegroundColor $deltaColor
        }

        $freedLabel = if ($Run.WhatIfOnly) { 'Est. Reclaimable' } else { 'Reported Freed' }
        Write-Host '--------------------------------------------------' -ForegroundColor Cyan
        Write-Host " $freedLabel : $(Format-UscBytes -Bytes $Run.TotalBytesFreed)" -ForegroundColor Green
    }

    $cleanOps = @($Run.Results) | Where-Object { $_.Category -in 'Clean','Checkpoint','Configure' }
    if ($cleanOps.Count -gt 0) {
        Write-Host '--------------------------------------------------' -ForegroundColor Cyan
        Write-Host ' OPERATIONS' -ForegroundColor Green
        foreach ($op in $cleanOps) {
            Write-UscOperationConsole -Result $op -WhatIfOnly:([bool]$Run.WhatIfOnly)
        }
    }

    $failed = @($Run.Results) | Where-Object { $_.Status -eq 'Failed' }
    if ($failed.Count -gt 0) {
        Write-Host '--------------------------------------------------' -ForegroundColor Cyan
        Write-Host " $($failed.Count) operation(s) failed - see log for details." -ForegroundColor Red
    }

    Write-Host '--------------------------------------------------' -ForegroundColor Cyan
    Write-Host ' OUTPUT' -ForegroundColor Green
    Write-Host " Log : $LogFile" -ForegroundColor Gray
    $htmlReport = @($ReportPaths) | Where-Object { $_ -like '*.html' } | Select-Object -First 1
    foreach ($report in @($ReportPaths)) {
        Write-Host "  - $report" -ForegroundColor Yellow
    }
    if ($htmlReport -and (Test-Path -LiteralPath $htmlReport) -and [Environment]::UserInteractive) {
        $open = Read-Host 'Open HTML report in browser? (y/N)'
        if ($open -match '^[yY]') {
            Start-Process -FilePath $htmlReport
        }
    }
    Write-Host '==================================================' -ForegroundColor Cyan
}

function Show-UscLogo {
    Write-Host '                 ___' -ForegroundColor Magenta
    Write-Host '     \          /   \       ___  _   _     _  __  ___   _   _' -ForegroundColor Magenta
    Write-Host '  ====\        /     \     | __|/ \ | |   | |/ / /   \ | \ | |' -ForegroundColor Magenta
    Write-Host ' ======\______/   _   \    | _|/ _ \| |__ |   <  | () | |  \| |' -ForegroundColor DarkMagenta
    Write-Host ' =======_        //\   >   |_|/_/ \_\____||_|\_\ \___/ |_|\___|' -ForegroundColor DarkMagenta
    Write-Host '  ======/       //  \_/    F A L K O N   S Y S T E M   U T I L' -ForegroundColor Cyan
    Write-Host '    ===/_______//' -ForegroundColor Cyan
    Write-Host '==================================================' -ForegroundColor Cyan
}

function Show-UscMenu {
    [CmdletBinding()]
    param([psobject]$Config)

    $adminStatus = 'Standard User (Some functions restricted)'
    if (Test-UscAdministrator) { $adminStatus = 'Elevated (Admin)' }

    while ($true) {
        Clear-Host
        Show-UscLogo
        Write-Host " Privilege Context : $adminStatus" -ForegroundColor Yellow
        if ($Config.DryRunDefault) {
            Write-Host ' Dry Run Mode      : ON - cleanups simulate only (Settings to disable)' -ForegroundColor Yellow
        }
        Write-Host '--------------------------------------------------' -ForegroundColor Cyan
        Write-Host '[1] Diagnose System Space (All Drives)' -ForegroundColor Green
        Write-Host '[2] Run Safe Cleanup' -ForegroundColor Yellow
        Write-Host '[3] Run Aggressive Cleanup' -ForegroundColor Yellow
        Write-Host '[4] Run Nuclear Cleanup' -ForegroundColor Red
        Write-Host '[5] Configure Settings' -ForegroundColor Cyan
        Write-Host '[6] Deep Disk Analysis (Top Files)' -ForegroundColor Green
        Write-Host '[7] Component Store Analysis' -ForegroundColor Green
        Write-Host '[8] Schedule Weekly Safe Clean' -ForegroundColor Cyan
        Write-Host '[9] Code Signing Helper' -ForegroundColor DarkCyan
        Write-Host '[H] Run History & Comparison' -ForegroundColor DarkCyan
        Write-Host '[0] Exit' -ForegroundColor White
        Write-Host '==================================================' -ForegroundColor Cyan
        
        $selection = Read-Host 'Selection'
        switch ($selection) {
            '1' { return @{ Mode = 'Diagnose'; ConfirmNuclear = $false } }
            '2' { return @{ Mode = 'Safe'; ConfirmNuclear = $false } }
            '3' { return @{ Mode = 'Aggressive'; ConfirmNuclear = $false } }
            '4' { 
                $confirm = Read-Host 'Nuclear actions can permanently remove rollback state. Are you sure? (y/N)'
                if ($confirm -match '^[yY]') {
                    return @{ Mode = 'Nuclear'; ConfirmNuclear = $true }
                }
                break
            }
            '5' { Show-UscConfigEditor -Config $Config }
            '6' { return @{ Mode = 'DeepSpace'; ConfirmNuclear = $false } }
            '7' { return @{ Mode = 'ComponentStore'; ConfirmNuclear = $false } }
            '8' { Show-UscScheduleHelper; break }
            '9' { Show-UscSigningHelper; break }
            { $_ -in 'h','H' } { return @{ Mode = 'History'; ConfirmNuclear = $false } }
            '0' { return @{ Mode = 'Exit'; ConfirmNuclear = $false } }
            default { Write-Host 'Invalid choice, try again.'; Start-Sleep -Seconds 1 }
        }
    }
}

function Show-UscConfigEditor {
    param([psobject]$Config)

    while ($true) {
        Clear-Host
        if (Get-Command Show-UscLogo -ErrorAction SilentlyContinue) { Show-UscLogo }
        Write-Host '             CONFIGURATION SETTINGS               ' -ForegroundColor White -BackgroundColor Blue
        Write-Host '==================================================' -ForegroundColor Cyan
        Write-Host '[1] Global Framework Options (Dry Run, Safety, etc.)'
        Write-Host '[2] Safe Mode Target Cleaners'
        Write-Host '[3] Aggressive Mode Target Cleaners'
        Write-Host '[4] Nuclear Mode Target Cleaners'
        Write-Host '[5] View Exclusion Folders & Files'
        Write-Host '[6] Reset to Recommended Default Settings' -ForegroundColor Yellow
        Write-Host '[7] Save Configuration & Exit Editor' -ForegroundColor Green
        Write-Host '==================================================' -ForegroundColor Cyan
        $choice = Read-Host 'Selection'
        switch ($choice) {
            '1' { Show-UscConfigGlobal -Config $Config }
            '2' { Show-UscConfigSafe -Config $Config }
            '3' { Show-UscConfigAggressive -Config $Config }
            '4' { Show-UscConfigNuclear -Config $Config }
            '5' { 
                Write-Host 'Exclusions:'
                $Config.Exclusions | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }
                $null = Read-Host 'Press Enter to continue'
            }
            '6' {
                $defaults = Get-UscDefaultConfig
                foreach ($prop in $defaults.psobject.Properties) {
                    $Config.($prop.Name) = $prop.Value
                }
                Write-Host 'Configuration reset to default settings.' -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
            '7' { 
                Save-UscConfig -Config $Config -Path $script:ConfigPath
                Write-Host 'Settings saved successfully.' -ForegroundColor Green
                Start-Sleep -Seconds 1
                return
            }
        }
    }
}

function Show-UscConfigGlobal {
    param([psobject]$Config)
    while ($true) {
        Clear-Host
        if (Get-Command Show-UscLogo -ErrorAction SilentlyContinue) { Show-UscLogo }
        Write-Host '            GLOBAL FRAMEWORK OPTIONS              ' -ForegroundColor White -BackgroundColor Blue
        Write-Host '==================================================' -ForegroundColor Cyan
        Write-Host "[1] Toggle DryRunDefault          : $($Config.DryRunDefault)"
        Write-Host "[2] Toggle CreateRestorePoint     : $($Config.CreateRestorePoint)"
        Write-Host "[3] Toggle ConfirmNuclearActions  : $($Config.ConfirmNuclearActions)"
        Write-Host "[4] Toggle Storage Sense Support  : $($Config.EnableStorageSenseIntegration)"
        Write-Host '[5] Back to Settings Menu'
        Write-Host '==================================================' -ForegroundColor Cyan
        $choice = Read-Host 'Selection'
        switch ($choice) {
            '1' { $Config.DryRunDefault = -not $Config.DryRunDefault }
            '2' { $Config.CreateRestorePoint = -not $Config.CreateRestorePoint }
            '3' { $Config.ConfirmNuclearActions = -not $Config.ConfirmNuclearActions }
            '4' { $Config.EnableStorageSenseIntegration = -not $Config.EnableStorageSenseIntegration }
            '5' { return }
        }
    }
}

function Show-UscConfigSafe {
    param([psobject]$Config)
    while ($true) {
        Clear-Host
        if (Get-Command Show-UscLogo -ErrorAction SilentlyContinue) { Show-UscLogo }
        Write-Host '            SAFE CLEANER CONFIGURATION            ' -ForegroundColor White -BackgroundColor Blue
        Write-Host '==================================================' -ForegroundColor Cyan
        Write-Host "[1] Toggle Temp Directories       : $($Config.Safe.Temp)"
        Write-Host "[2] Toggle Recycle Bin Clear      : $($Config.Safe.RecycleBin)"
        Write-Host "[3] Toggle Windows Thumbnails     : $($Config.Safe.Thumbnails)"
        Write-Host "[4] Toggle Browser Cache Clear    : $($Config.Safe.BrowserCache)"
        Write-Host '[5] Back to Settings Menu'
        Write-Host '==================================================' -ForegroundColor Cyan
        $choice = Read-Host 'Selection'
        switch ($choice) {
            '1' { $Config.Safe.Temp = -not $Config.Safe.Temp }
            '2' { $Config.Safe.RecycleBin = -not $Config.Safe.RecycleBin }
            '3' { $Config.Safe.Thumbnails = -not $Config.Safe.Thumbnails }
            '4' { $Config.Safe.BrowserCache = -not $Config.Safe.BrowserCache }
            '5' { return }
        }
    }
}

function Show-UscConfigAggressive {
    param([psobject]$Config)
    while ($true) {
        Clear-Host
        if (Get-Command Show-UscLogo -ErrorAction SilentlyContinue) { Show-UscLogo }
        Write-Host '         AGGRESSIVE CLEANER CONFIGURATION         ' -ForegroundColor White -BackgroundColor Blue
        Write-Host '==================================================' -ForegroundColor Cyan
        Write-Host "[1] Toggle Windows Error Rep.     : $($Config.Aggressive.WindowsErrorReporting)"
        Write-Host "[2] Toggle Windows Update Cache   : $($Config.Aggressive.WindowsUpdateCache)"
        Write-Host "[3] Toggle GPU Shader Cache       : $($Config.Aggressive.GpuShaderCache)"
        Write-Host "[4] Toggle Browser Cache Clear    : $($Config.Aggressive.BrowserCache)"
        Write-Host "[5] Toggle DNS Cache Flush        : $($Config.Aggressive.DnsFlush)"
        Write-Host "[6] Toggle Windows Font Cache     : $($Config.Aggressive.FontCache)"
        Write-Host "[7] Toggle Delivery Optimization  : $($Config.Aggressive.DeliveryOptimization)"
        Write-Host '[8] Back to Settings Menu'
        Write-Host '==================================================' -ForegroundColor Cyan
        $choice = Read-Host 'Selection'
        switch ($choice) {
            '1' { $Config.Aggressive.WindowsErrorReporting = -not $Config.Aggressive.WindowsErrorReporting }
            '2' { $Config.Aggressive.WindowsUpdateCache = -not $Config.Aggressive.WindowsUpdateCache }
            '3' { $Config.Aggressive.GpuShaderCache = -not $Config.Aggressive.GpuShaderCache }
            '4' { $Config.Aggressive.BrowserCache = -not $Config.Aggressive.BrowserCache }
            '5' { $Config.Aggressive.DnsFlush = -not $Config.Aggressive.DnsFlush }
            '6' { $Config.Aggressive.FontCache = -not $Config.Aggressive.FontCache }
            '7' { $Config.Aggressive.DeliveryOptimization = -not $Config.Aggressive.DeliveryOptimization }
            '8' { return }
        }
    }
}

function Show-UscConfigNuclear {
    param([psobject]$Config)
    while ($true) {
        Clear-Host
        if (Get-Command Show-UscLogo -ErrorAction SilentlyContinue) { Show-UscLogo }
        Write-Host '          NUCLEAR CLEANER CONFIGURATION           ' -ForegroundColor White -BackgroundColor Blue
        Write-Host '==================================================' -ForegroundColor Cyan
        Write-Host "[1] Toggle System Crash Dumps     : $($Config.Nuclear.CrashDumps)"
        Write-Host "[2] Toggle WinSxS ResetBase       : $($Config.Nuclear.ComponentStoreResetBase)"
        Write-Host "[3] Toggle Delete Shadow Copies   : $($Config.Nuclear.DeleteShadowCopies)"
        Write-Host "[4] Toggle Remove Restore Points  : $($Config.Nuclear.RemoveRestorePoints)"
        Write-Host "[5] Toggle Purge Update Rollbacks : $($Config.Nuclear.PurgeUpdateRollback)"
        Write-Host '[6] Back to Settings Menu'
        Write-Host '==================================================' -ForegroundColor Cyan
        $choice = Read-Host 'Selection'
        switch ($choice) {
            '1' { $Config.Nuclear.CrashDumps = -not $Config.Nuclear.CrashDumps }
            '2' { $Config.Nuclear.ComponentStoreResetBase = -not $Config.Nuclear.ComponentStoreResetBase }
            '3' { $Config.Nuclear.DeleteShadowCopies = -not $Config.Nuclear.DeleteShadowCopies }
            '4' { $Config.Nuclear.RemoveRestorePoints = -not $Config.Nuclear.RemoveRestorePoints }
            '5' { $Config.Nuclear.PurgeUpdateRollback = -not $Config.Nuclear.PurgeUpdateRollback }
            '6' { return }
        }
    }
}

function Show-UscSigningHelper {
    Clear-Host
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host '            CODE-SIGNING UTILITY MENU             ' -ForegroundColor White -BackgroundColor Blue
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host '[1] Generate Code-Signing Certificate & Trust Local'
    Write-Host '[2] Sign All Cleaner Script Modules (*.ps1, *.psm1)'
    Write-Host '[3] Back'
    Write-Host '==================================================' -ForegroundColor Cyan
    $choice = Read-Host 'Selection'
    if ($choice -eq '1') {
        if (-not (Test-UscAdministrator)) {
            Write-Host 'Administrator context is required to trust local certificate.' -ForegroundColor Red
            $null = Read-Host 'Press Enter to continue'
            return
        }
        try {
            $cert = New-UscSelfSignedCert -ImportToRoot -ErrorAction Stop
            Write-Host "Self-signed certificate created successfully: $($cert.Thumbprint)" -ForegroundColor Green
        }
        catch {
            Write-Host "Error creating certificate: $_" -ForegroundColor Red
        }
        $null = Read-Host 'Press Enter to continue'
    }
    elseif ($choice -eq '2') {
        # Find a code signing cert in CurrentUser
        $certs = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue)
        if ($certs.Count -eq 0) {
            Write-Host 'No code signing certificates found. Please run Option [1] first to generate one.' -ForegroundColor Red
            $null = Read-Host 'Press Enter to continue'
            return
        }
        $cert = $certs[0]
        Write-Host "Signing cleaner scripts with certificate: $($cert.Subject)..."
        $files = Get-ChildItem $PSScriptRoot -Include *.ps1,*.psm1 -Recurse
        foreach ($file in $files) {
            Set-UscFileSignature -Path $file.FullName -Certificate $cert | Out-Null
        }
        Write-Host 'All cleaner files signed. Re-run app to verify signature status.' -ForegroundColor Green
        $null = Read-Host 'Press Enter to continue'
    }
}

function Show-UscScheduleHelper {
    Clear-Host
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host '            SCHEDULED TASK MANAGEMENT             ' -ForegroundColor White -BackgroundColor Blue
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host '[1] Install Weekly Safe Cleaner Scheduled Task'
    Write-Host '[2] Remove Weekly Safe Cleaner Scheduled Task'
    Write-Host '[3] Back'
    Write-Host '==================================================' -ForegroundColor Cyan
    $choice = Read-Host 'Selection'
    if ($choice -eq '1') {
        $res = Register-UscScheduledTask -ScriptPath $PSCommandPath
        Write-Host "Task installed: $($res.Status) - $($res.Message)" -ForegroundColor Green
        $null = Read-Host 'Press Enter to continue'
    }
    elseif ($choice -eq '2') {
        $res = Unregister-UscScheduledTask
        Write-Host "Task status: $($res.Status) - $($res.Message)" -ForegroundColor Green
        $null = Read-Host 'Press Enter to continue'
    }
}

function Invoke-UscPostCleanVerification {
    param(
        [psobject]$Config,
        [string]$Mode
    )
    
    if ($Mode -notin 'Safe', 'Aggressive', 'Nuclear') {
        return
    }

    Write-Host ""
    Write-Host "[*] Running post-cleanup verification check..." -ForegroundColor Yellow
    
    $remainingBytes = 0
    
    # Measure remaining in Temp
    $targets = Get-UscTempTargets -Config $Config
    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target.Path) {
            $files = Get-ChildItem -LiteralPath $target.Path -Force -Recurse -File -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $remainingBytes += [Int64]$f.Length
            }
        }
    }

    # Measure remaining in BrowserCache if applicable
    $cleanBrowser = $Config.Safe.BrowserCache -or ($Mode -in 'Aggressive', 'Nuclear' -and $Config.Aggressive.BrowserCache)
    if ($cleanBrowser) {
        $targets = Get-UscBrowserCacheTargets
        foreach ($target in $targets) {
            foreach ($sub in $target.SubDirs) {
                $fullSub = Join-Path $target.Path $sub
                if (Test-Path -LiteralPath $fullSub) {
                    $files = Get-ChildItem -LiteralPath $fullSub -Force -Recurse -File -ErrorAction SilentlyContinue
                    foreach ($f in $files) {
                        $remainingBytes += [Int64]$f.Length
                    }
                }
            }
        }
    }
    
    if ($remainingBytes -gt 1MB) {
        $sizeFormatted = Format-UscBytes -Bytes $remainingBytes
        Write-Host "[!] Verification: $sizeFormatted of locked/active files could not be cleaned." -ForegroundColor Yellow
        Write-Host "    -> Suggestion: Close running apps (browsers, game launchers) and run again," -ForegroundColor Gray
        Write-Host "       or reboot and run FalkonSysUtils to clean system-locked temporary files." -ForegroundColor Gray
    } else {
        Write-Host "[+] Verification: Cleanup was 100% successful! No significant residue left." -ForegroundColor Green
    }
    Write-Host ""
}

# Main script flow execution
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $script:ConfigPath = Join-Path $PSScriptRoot 'Config\settings.json'
}
else {
    $script:ConfigPath = $ConfigPath
}

$config = Read-UscConfig -Path $script:ConfigPath
$config.LogDirectory = [Environment]::ExpandEnvironmentVariables($config.LogDirectory)
$config.ReportDirectory = [Environment]::ExpandEnvironmentVariables($config.ReportDirectory)

$dryRun = [bool]($WhatIfOnly -or $config.DryRunDefault)
$script:BeforeSnapshot = @(Get-UscDriveSnapshot)

if ($PSCmdlet.ParameterSetName -eq 'Menu') {
    $firstRunFile = Join-Path $PSScriptRoot 'Config\.firstrun'
    if (-not (Test-Path $firstRunFile)) {
        Clear-Host
        if (Get-Command Show-UscLogo -ErrorAction SilentlyContinue) { Show-UscLogo }
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host "        WELCOME TO FALKON SYSTEM CLEANER          " -ForegroundColor White -BackgroundColor Blue
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host "It looks like this is your first time running the utility!" -ForegroundColor Yellow
        Write-Host "We recommend following this optimized workflow:" -ForegroundColor Gray
        Write-Host " 1. Run [Diagnose] to analyze your current disk state." -ForegroundColor Green
        Write-Host " 2. Run [Safe Cleanup] to remove safe caches without risks." -ForegroundColor Green
        Write-Host "==================================================" -ForegroundColor Cyan
        $null = Read-Host "Press Enter to initialize configuration and open menu"
        try {
            $null = New-Item -ItemType File -Path $firstRunFile -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    # Interactive TUI Loop
    while ($true) {
        $runId = Get-Date -Format 'yyyyMMdd-HHmmss'
        $logFile = Initialize-UscLogger -LogDirectory $config.LogDirectory -RunId $runId
        
        # Re-read config in case settings were changed in config editor
        $config = Read-UscConfig -Path $script:ConfigPath
        $config.LogDirectory = [Environment]::ExpandEnvironmentVariables($config.LogDirectory)
        $config.ReportDirectory = [Environment]::ExpandEnvironmentVariables($config.ReportDirectory)
        $dryRun = [bool]($WhatIfOnly -or $config.DryRunDefault)

        $choice = Show-UscMenu -Config $config
        $mode = $choice['Mode']
        if ($mode -eq 'Exit') { break }

        $confirmedNuke = $false
        if ($choice.ContainsKey('ConfirmNuclear')) {
            $confirmedNuke = [bool]$choice['ConfirmNuclear']
        }

        if ($dryRun -and $mode -in 'Safe','Aggressive','Nuclear') {
            Write-Host ''
            Write-Host ' Dry run is enabled - no files will be deleted.' -ForegroundColor Yellow
            $runReal = Read-Host 'Run cleanup for real this time? (y/N)'
            if ($runReal -match '^[yY]') {
                $dryRun = $false
            }
        }

        $script:BeforeSnapshot = @(Get-UscDriveSnapshot)
        $script:Started = Get-Date

        Write-UscLog -Level Audit -Message 'Run started' -Data @{ Mode = $mode; WhatIfOnly = $dryRun; ConfigPath = $script:ConfigPath }
        $results = [System.Collections.Generic.List[object]]::new()

        try {
            switch ($mode) {
                'Diagnose' {
                    Clear-Host
                    Show-UscLogo
                    Write-Host '             SYSTEM SPACE DIAGNOSIS               ' -ForegroundColor White -BackgroundColor Blue
                    Write-Host '==================================================' -ForegroundColor Cyan
                    
                    Write-Host '  Scanning system drives & folders...' -ForegroundColor Gray
                    
                    Start-UscProgress -Activity 'Diagnosing' -Status 'Scanning drives and estimating cache sizes...' -Id 1
                    $drives = @(Get-UscDriveSnapshot)
                    $estimate = Get-UscDiagnosisEstimate -Config $config
                    Complete-UscProgress -Activity 'Diagnosing' -Id 1
                    
                    Write-Host ' DRIVE CAPACITY:' -ForegroundColor Green
                    foreach ($d in $drives) {
                        $freeFormatted = Format-UscBytes -Bytes $d.FreeSpace
                        $sizeFormatted = Format-UscBytes -Bytes $d.Size
                        $usedFormatted = Format-UscBytes -Bytes $d.UsedSpace
                        Write-Host "  - Drive $($d.Drive) [$($d.VolumeName)] ($($d.FileSystem)):"
                        Write-Host "    * Free Space: $freeFormatted ($($d.PercentFree)% free)" -ForegroundColor Green
                        Write-Host "    * Used Space: $usedFormatted" -ForegroundColor Gray
                        Write-Host "    * Total Size: $sizeFormatted" -ForegroundColor Gray
                    }
                    
                    Write-Host '--------------------------------------------------' -ForegroundColor Cyan
                    Write-Host ' CLEANUP ESTIMATES BY MODE:' -ForegroundColor Green
                    Write-Host "  - [Safe Mode]      : $(Format-UscBytes -Bytes $estimate.Safe)" -ForegroundColor Yellow
                    Write-Host "    * Temp Folders   : $(Format-UscBytes -Bytes $estimate.Breakdown.Temp)" -ForegroundColor Gray
                    Write-Host "    * Recycle Bin    : $(Format-UscBytes -Bytes $estimate.Breakdown.RecycleBin)" -ForegroundColor Gray
                    Write-Host "  - [Aggressive Mode]: $(Format-UscBytes -Bytes $estimate.Aggressive)" -ForegroundColor Yellow
                    Write-Host "    * Browser Cache  : $(Format-UscBytes -Bytes $estimate.Breakdown.Browser)" -ForegroundColor Gray
                    Write-Host "    * GPU Cache      : $(Format-UscBytes -Bytes $estimate.Breakdown.GpuShader)" -ForegroundColor Gray
                    Write-Host "    * Windows Update : $(Format-UscBytes -Bytes $estimate.Breakdown.WindowsUpdate)" -ForegroundColor Gray
                    Write-Host "    * WER Reports    : $(Format-UscBytes -Bytes $estimate.Breakdown.WER)" -ForegroundColor Gray
                    Write-Host "  - [Nuclear Mode]   : $(Format-UscBytes -Bytes $estimate.Nuclear)" -ForegroundColor Red
                    Write-Host "    * WinSxS Temp    : $(Format-UscBytes -Bytes $estimate.Breakdown.ComponentStore)" -ForegroundColor Gray
                    Write-Host "    * Crash Dumps    : $(Format-UscBytes -Bytes $estimate.Breakdown.CrashDumps)" -ForegroundColor Gray
                    Write-Host '==================================================' -ForegroundColor Cyan
                    
                    $results.Add((New-UscOperationResult -Name 'Diagnosis' -Category Analyze -Status Succeeded -Message "Scanned $($drives.Count) drives. Nuclear cleanable estimate: $(Format-UscBytes -Bytes $estimate.Nuclear)"))
                }
                'Analyze' { 
                    $results.AddRange(@(Invoke-UscAnalysis -Config $config)) 
                }
                'DeepSpace' {
                    $deepScan = Get-UscDeepSpaceAnalysis -RootPath $env:SystemDrive.TrimEnd('\') -MaxItems 10
                    Write-Host '==================================================' -ForegroundColor Cyan
                    Write-Host '            DEEP DISK SPACE ANALYSIS              ' -ForegroundColor White -BackgroundColor Blue
                    Write-Host '==================================================' -ForegroundColor Cyan
                    Write-Host "Scanned items in: $($deepScan.RootPath) ($($deepScan.TotalInspectedFiles) files)"
                    Write-Host 'Category Breakdown:'
                    Write-Host " - Caches       : $(Format-UscBytes -Bytes $deepScan.Categories.Caches)"
                    Write-Host " - Logs         : $(Format-UscBytes -Bytes $deepScan.Categories.Logs)"
                    Write-Host " - Dumps        : $(Format-UscBytes -Bytes $deepScan.Categories.Dumps)"
                    Write-Host " - Updates/Temp : $(Format-UscBytes -Bytes $deepScan.Categories.Updates)"
                    Write-Host " - Other System : $(Format-UscBytes -Bytes $deepScan.Categories.SystemOther)"
                    Write-Host 'Top 10 Largest Files:' -ForegroundColor Yellow
                    $deepScan.TopFiles | ForEach-Object {
                        $fileUri = ([uri]$_.Path).AbsoluteUri
                        Write-Host " - $(Format-UscBytes -Bytes $_.Size) : $fileUri"
                    }
                    Write-Host '==================================================' -ForegroundColor Cyan
                    $results.Add((New-UscOperationResult -Name 'Deep Space Analysis' -Category Analyze -Status Succeeded -Message "Scanned $($deepScan.TotalInspectedFiles) files"))
                }
                'ComponentStore' { 
                    $analysis = Get-UscComponentStoreAnalysis
                    $results.Add((New-UscOperationResult -Name 'Component Store Analysis' -Category Analyze -Status Succeeded -Metadata @{ Analysis = $analysis })) 
                    Write-Host "Store Analysis Status: Cleanup recommended? $($analysis.RecommendedCleanup)" -ForegroundColor Yellow
                }
                'History' {
                    Clear-Host
                    if (Get-Command Show-UscLogo -ErrorAction SilentlyContinue) { Show-UscLogo }
                    Write-Host '              RUN HISTORY & COMPARISON             ' -ForegroundColor White -BackgroundColor Blue
                    Write-Host '==================================================' -ForegroundColor Cyan
                    Write-Host '[1] Show Last 10 Runs'
                    Write-Host '[2] Compare Latest vs Previous Run'
                    Write-Host '[3] Export Trend Data (CSV)'
                    Write-Host '[4] Back'
                    Write-Host '==================================================' -ForegroundColor Cyan
                    $hChoice = Read-Host 'Selection'
                    switch ($hChoice) {
                        '1' {
                            Show-UscRunHistory
                            $null = Read-Host 'Press Enter to continue'
                        }
                        '2' {
                            Compare-UscLastTwoRuns
                            $null = Read-Host 'Press Enter to continue'
                        }
                        '3' {
                            $trendPath = Export-UscHistoryTrend
                            if ($trendPath) {
                                Write-Host "[+] Trend CSV exported: $trendPath" -ForegroundColor Green
                            }
                            $null = Read-Host 'Press Enter to continue'
                        }
                    }
                    continue
                }
                default { 
                    $results.AddRange(@(Invoke-UscCleanupMode -Mode $mode -Config $config -WhatIfOnly:$dryRun -ConfirmNuclear:$confirmedNuke)) 
                    if (-not $dryRun) {
                        Invoke-UscPostCleanVerification -Config $config -Mode $mode
                    }
                }
            }
        }
        catch {
            Write-UscLog -Level Critical -Message 'Run failed' -Exception $_.Exception
            $results.Add((New-UscOperationResult -Name 'Run' -Category Clean -Status Failed -Message $_.Exception.Message))
        }

        $run = New-UscRunRecord -RunId $runId -Mode $mode -Results @($results) -Config $config -WhatIfOnly:$dryRun
        $reportPaths = [System.Collections.Generic.List[string]]::new()

        if ($GenerateReport -or $mode -in 'Diagnose','Analyze','DeepSpace','ComponentStore','Safe','Aggressive','Nuclear') {
            $reportPaths.Add((New-UscJsonReport -Run $run -OutputDirectory $config.ReportDirectory))
            $reportPaths.Add((New-UscCsvReport -Results @($results) -OutputDirectory $config.ReportDirectory -RunId $runId))
            $reportPaths.Add((New-UscHtmlReport -Run $run -OutputDirectory $config.ReportDirectory))
        }

        # Persist run to history store
        if (Get-Command Save-UscRunHistory -ErrorAction SilentlyContinue) {
            Save-UscRunHistory -Run $run
        }

        Write-UscLog -Level Audit -Message 'Run finished' -Data @{ Mode = $mode; TotalBytesFreed = $run.TotalBytesFreed; Reports = @($reportPaths); LogFile = $logFile }

        Show-UscResultsSummary -Run $run -RunId $runId -LogFile $logFile -ReportPaths @($reportPaths)
        
        $null = Read-Host 'Press Enter to return to the main menu'
    }
}
else {
    # Non-interactive CLI Mode (runs once)
    $runId = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:Started = Get-Date
    $logFile = Initialize-UscLogger -LogDirectory $config.LogDirectory -RunId $runId
    
    $mode = $PSCmdlet.ParameterSetName
    if ($Safe) { $mode = 'Safe' }
    elseif ($Aggressive) { $mode = 'Aggressive' }
    elseif ($Nuclear) { $mode = 'Nuclear' }
    elseif ($Analyze) { $mode = 'Diagnose' }
    elseif ($ComponentStore) { $mode = 'ComponentStore' }
    elseif ($InstallScheduledTask) { $mode = 'InstallScheduledTask' }
    elseif ($RemoveScheduledTask) { $mode = 'RemoveScheduledTask' }

    Write-UscLog -Level Audit -Message 'Run started' -Data @{ Mode = $mode; WhatIfOnly = $dryRun; ConfigPath = $script:ConfigPath }
    $results = [System.Collections.Generic.List[object]]::new()

    try {
        switch ($mode) {
            'Diagnose' {
                Start-UscProgress -Activity 'Diagnosing' -Status 'Scanning drives and estimating cache sizes...' -Id 1
                $drives = @(Get-UscDriveSnapshot)
                $estimate = Get-UscDiagnosisEstimate -Config $config
                Complete-UscProgress -Activity 'Diagnosing' -Id 1
                
                Write-Host '==================================================' -ForegroundColor Cyan
                Write-Host '             SYSTEM SPACE DIAGNOSIS               ' -ForegroundColor White -BackgroundColor Blue
                Write-Host '==================================================' -ForegroundColor Cyan
                Write-Host ' DRIVE CAPACITY:' -ForegroundColor Green
                foreach ($d in $drives) {
                    Write-Host "  - Drive $($d.Drive) [$($d.VolumeName)] ($($d.FileSystem)):"
                    Write-Host "    * Free Space: $(Format-UscBytes -Bytes $d.FreeSpace) ($($d.PercentFree)% free)" -ForegroundColor Green
                    Write-Host "    * Used Space: $(Format-UscBytes -Bytes $d.UsedSpace)" -ForegroundColor Gray
                    Write-Host "    * Total Size: $(Format-UscBytes -Bytes $d.Size)" -ForegroundColor Gray
                }
                Write-Host '--------------------------------------------------' -ForegroundColor Cyan
                Write-Host ' CLEANUP ESTIMATES BY MODE:' -ForegroundColor Green
                Write-Host "  - [Safe Mode]      : $(Format-UscBytes -Bytes $estimate.Safe)" -ForegroundColor Yellow
                Write-Host "  - [Aggressive Mode]: $(Format-UscBytes -Bytes $estimate.Aggressive)" -ForegroundColor Yellow
                Write-Host "  - [Nuclear Mode]   : $(Format-UscBytes -Bytes $estimate.Nuclear)" -ForegroundColor Red
                Write-Host '==================================================' -ForegroundColor Cyan

                $results.Add((New-UscOperationResult -Name 'Diagnosis' -Category Analyze -Status Succeeded -Message "Scanned $($drives.Count) drives. Nuclear cleanable estimate: $(Format-UscBytes -Bytes $estimate.Nuclear)"))
            }
            'Analyze' { 
                $results.AddRange(@(Invoke-UscAnalysis -Config $config)) 
            }
            'ComponentStore' { 
                $analysis = Get-UscComponentStoreAnalysis
                $results.Add((New-UscOperationResult -Name 'Component Store Analysis' -Category Analyze -Status Succeeded -Metadata @{ Analysis = $analysis })) 
            }
            'InstallScheduledTask' { 
                $results.Add((Register-UscScheduledTask -ScriptPath $PSCommandPath)) 
            }
            'RemoveScheduledTask' { 
                $results.Add((Unregister-UscScheduledTask)) 
            }
            default { 
                $results.AddRange(@(Invoke-UscCleanupMode -Mode $mode -Config $config -WhatIfOnly:$dryRun -ConfirmNuclear:$ConfirmNuclear)) 
            }
        }
    }
    catch {
        Write-UscLog -Level Critical -Message 'Run failed' -Exception $_.Exception
        $results.Add((New-UscOperationResult -Name 'Run' -Category Clean -Status Failed -Message $_.Exception.Message))
    }

    $run = New-UscRunRecord -RunId $runId -Mode $mode -Results @($results) -Config $config -WhatIfOnly:$dryRun
    $reportPaths = [System.Collections.Generic.List[string]]::new()

    if ($GenerateReport -or $mode -in 'Diagnose','Analyze','Safe','Aggressive','Nuclear') {
        $reportPaths.Add((New-UscJsonReport -Run $run -OutputDirectory $config.ReportDirectory))
        $reportPaths.Add((New-UscCsvReport -Results @($results) -OutputDirectory $config.ReportDirectory -RunId $runId))
        $reportPaths.Add((New-UscHtmlReport -Run $run -OutputDirectory $config.ReportDirectory))
    }

    Write-UscLog -Level Audit -Message 'Run finished' -Data @{ Mode = $mode; TotalBytesFreed = $run.TotalBytesFreed; Reports = @($reportPaths); LogFile = $logFile }

    Show-UscResultsSummary -Run $run -RunId $runId -LogFile $logFile -ReportPaths @($reportPaths)

    [pscustomobject]@{
        RunId = $runId
        Mode = $mode
        WhatIfOnly = $dryRun
        TotalBytesFreed = $run.TotalBytesFreed
        LogFile = $logFile
        Reports = @($reportPaths)
        Results = @($results)
    }
}

