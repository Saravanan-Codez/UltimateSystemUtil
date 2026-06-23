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
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "       ULTIMATE SYSTEM CLEANER WEB BOOTSTRAP       " -ForegroundColor White -BackgroundColor Blue
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "Running in web-load context. Bootstrapping files..." -ForegroundColor Gray
    
    $zipUrl = "https://github.com/Saravanan-Codez/UltimateSystemCleaner/archive/refs/heads/main.zip"
    $tempDir = Join-Path $env:TEMP "UltimateSystemCleaner-Bootstrap"
    
    try {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
        $zipFile = Join-Path $tempDir "repo.zip"
        Write-Host "Downloading repository package from GitHub..." -ForegroundColor Gray
        
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -Uri $zipUrl -OutFile $zipFile -ErrorAction Stop
        
        Write-Host "Extracting files to temp workspace..." -ForegroundColor Gray
        Expand-Archive -Path $zipFile -DestinationPath $tempDir -Force -ErrorAction Stop
        
        $expandedFolder = Get-ChildItem -LiteralPath $tempDir -Directory | Select-Object -First 1
        if ($expandedFolder) {
            $launcherPath = Join-Path $expandedFolder.FullName "UltimateSystemCleaner.ps1"
            Write-Host "Running launcher in localized workspace..." -ForegroundColor Green
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
            Write-Error "Failed to locate extracted launcher files in temp directory."
        }
    }
    catch {
        Write-Error "Web bootstrap failed: $($_.Exception.Message)"
    }
    return
}

# Unblock downloaded script files to support manual ZIP downloads
Get-ChildItem -LiteralPath $PSScriptRoot -Include *.ps1,*.psm1 -Recurse -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import Core modules first to enable signing check
$sigModulePath = Join-Path $PSScriptRoot 'Core\Signature.psm1'
Import-Module $sigModulePath -Force

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
    'Reports\HtmlReport.psm1'
)

# Audit signatures for security compliance
$unsignedCount = 0
foreach ($module in $modulePaths) {
    $fullPath = Join-Path $PSScriptRoot $module
    if (-not (Test-UscFileSignature -Path $fullPath)) {
        $unsignedCount++
    }
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

    if ($Config.CreateRestorePoint -and -not $WhatIfOnly) {
        Update-UscProgress -Activity "Ultimate System Cleaner: $Mode" -Status 'Creating System Restore Point...' -PercentComplete 5 -Id 1
        $results.Add((New-UscRestorePoint -Description "Ultimate System Cleaner $Mode mode"))
    }

    # Safe operations
    Update-UscProgress -Activity "Ultimate System Cleaner: $Mode" -Status 'Executing Safe Cleaners...' -PercentComplete 15 -Id 1
    if ($Config.Safe.Temp) { 
        Start-UscProgress -Activity 'Cleaning Temp Folders' -Status 'Processing User/System temporary items...' -Id 2 -ParentId 1
        $results.AddRange(@(Invoke-UscTempCleanup -Config $Config -WhatIfOnly:$WhatIfOnly)) 
        Complete-UscProgress -Activity 'Cleaning Temp Folders' -Id 2
    }
    if ($Config.Safe.RecycleBin) { 
        $results.Add((Invoke-UscRecycleBinCleanup -WhatIfOnly:$WhatIfOnly)) 
    }

    # Aggressive operations
    if ($Mode -in 'Aggressive','Nuclear') {
        Update-UscProgress -Activity "Ultimate System Cleaner: $Mode" -Status 'Executing Aggressive Cleaners...' -PercentComplete 40 -Id 1
        
        if ($Config.Aggressive.WindowsErrorReporting) { 
            $results.AddRange(@(Invoke-UscWerCleanup -Config $Config -WhatIfOnly:$WhatIfOnly)) 
        }
        if ($Config.Aggressive.GpuShaderCache) { 
            $results.AddRange(@(Invoke-UscGpuCacheCleanup -Config $Config -WhatIfOnly:$WhatIfOnly)) 
        }
        if ($Config.Aggressive.BrowserCache) { 
            Start-UscProgress -Activity 'Cleaning Browser Cache' -Status 'Scanning chromium and gecko profiles...' -Id 3 -ParentId 1
            $results.AddRange(@(Invoke-UscBrowserCacheCleanup -Config $Config -WhatIfOnly:$WhatIfOnly)) 
            Complete-UscProgress -Activity 'Cleaning Browser Cache' -Id 3
        }
        if ($Config.Aggressive.WindowsUpdateCache) { 
            $results.Add((Invoke-UscWindowsUpdateCleanup -Config $Config -WhatIfOnly:$WhatIfOnly)) 
        }
        if ($Config.EnableStorageSenseIntegration) { 
            $results.Add((Invoke-UscStorageSense -WhatIfOnly:$WhatIfOnly)) 
        }
    }

    # Nuclear operations
    if ($Mode -eq 'Nuclear') {
        Update-UscProgress -Activity "Ultimate System Cleaner: $Mode" -Status 'Executing Nuclear Cleaners...' -PercentComplete 75 -Id 1
        if (-not $ConfirmNuclear -and $Config.ConfirmNuclearActions) {
            $results.Add((New-UscOperationResult -Name 'Nuclear Mode' -Category Clean -Status Skipped -Message 'Skipped destructive operations. Re-run with -ConfirmNuclear to unlock configured nuclear tasks.'))
        }
        else {
            if ($Config.Nuclear.CrashDumps) { 
                $results.AddRange(@(Invoke-UscDumpCleanup -Config $Config -WhatIfOnly:$WhatIfOnly)) 
            }
            # Start SxS Component reset base
            $results.Add((Invoke-UscComponentStoreCleanup -ResetBase:([bool]$Config.Nuclear.ComponentStoreResetBase) -WhatIfOnly:$WhatIfOnly))
            $results.AddRange(@(Invoke-UscNuclearRecoveryCleanup -Config $Config -Confirmed:$ConfirmNuclear -WhatIfOnly:$WhatIfOnly))
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

function Show-UscMenu {
    [CmdletBinding()]
    param([psobject]$Config)

    $adminStatus = 'Standard User (Some functions restricted)'
    if (Test-UscAdministrator) { $adminStatus = 'Elevated (Admin)' }

    $sigStatus = "$unsignedCount Unsigned Modules Found"
    $sigColor = 'Yellow'
    if ($unsignedCount -eq 0) {
        $sigStatus = 'All Modules Validly Signed'
        $sigColor = 'Green'
    }

    while ($true) {
        Clear-Host
        Write-Host '==================================================' -ForegroundColor Cyan
        Write-Host '          ULTIMATE SYSTEM CLEANER v0.2            ' -ForegroundColor White -BackgroundColor Blue
        Write-Host '==================================================' -ForegroundColor Cyan
        Write-Host " Privilege Context : $adminStatus" -ForegroundColor Yellow
        Write-Host " Signature Audit   : $sigStatus" -ForegroundColor $sigColor
        
        $drive = Get-UscDriveSnapshot | Select-Object -First 1
        if ($drive) {
            $freeFormatted = Format-UscBytes -Bytes $drive.FreeSpace
            $sizeFormatted = Format-UscBytes -Bytes $drive.Size
            Write-Host " Drive $($drive.Drive) Storage     : $freeFormatted free of $sizeFormatted ($($drive.PercentFree)% free)" -ForegroundColor Gray
        }
        Write-Host '--------------------------------------------------' -ForegroundColor Cyan
        Write-Host '[1] Analyze Disk Usage (Find Opportunities)' -ForegroundColor Green
        Write-Host '[2] Deep Disk Space Analysis (Top Files & Folders)' -ForegroundColor Green
        Write-Host '[3] Run Safe Cleanup (Temp, cache, recycle bin)' -ForegroundColor Yellow
        Write-Host '[4] Run Aggressive Cleanup (Safe + WER + update cache)' -ForegroundColor Yellow
        Write-Host '[5] Run Nuclear Cleanup (Aggressive + restore/resetbase)' -ForegroundColor Red
        Write-Host '[6] Analyze SxS Component Store' -ForegroundColor Gray
        Write-Host '[7] Configure Settings (settings.json)' -ForegroundColor Cyan
        Write-Host '[8] Local Code-Signing Utilities' -ForegroundColor Magenta
        Write-Host '[9] Scheduled Task Management' -ForegroundColor Magenta
        Write-Host '[0] Exit' -ForegroundColor White
        Write-Host '==================================================' -ForegroundColor Cyan
        
        $selection = Read-Host 'Selection'
        switch ($selection) {
            '1' { return @{ Mode = 'Analyze'; ConfirmNuclear = $false } }
            '2' { return @{ Mode = 'DeepSpace'; ConfirmNuclear = $false } }
            '3' { return @{ Mode = 'Safe'; ConfirmNuclear = $false } }
            '4' { return @{ Mode = 'Aggressive'; ConfirmNuclear = $false } }
            '5' { 
                $confirm = Read-Host 'Nuclear actions can permanently remove rollback state. Are you sure? (y/N)'
                if ($confirm -eq 'y') {
                    return @{ Mode = 'Nuclear'; ConfirmNuclear = $true }
                }
                break
            }
            '6' { return @{ Mode = 'ComponentStore'; ConfirmNuclear = $false } }
            '7' { Show-UscConfigEditor -Config $Config }
            '8' { Show-UscSigningHelper }
            '9' { Show-UscScheduleHelper }
            '0' { return @{ Mode = 'Exit'; ConfirmNuclear = $false } }
            default { Write-Host 'Invalid choice, try again.'; Start-Sleep -Seconds 1 }
        }
    }
}

function Show-UscConfigEditor {
    param([psobject]$Config)

    while ($true) {
        Clear-Host
        Write-Host '==================================================' -ForegroundColor Cyan
        Write-Host '             CONFIGURATION SETTINGS               ' -ForegroundColor White -BackgroundColor Blue
        Write-Host '==================================================' -ForegroundColor Cyan
        Write-Host "[1] Toggle DryRunDefault          : $($Config.DryRunDefault)"
        Write-Host "[2] Toggle CreateRestorePoint     : $($Config.CreateRestorePoint)"
        Write-Host "[3] Toggle ConfirmNuclearActions  : $($Config.ConfirmNuclearActions)"
        Write-Host "[4] Toggle Storage Sense Support  : $($Config.EnableStorageSenseIntegration)"
        Write-Host '[5] Show Config Exclusions'
        Write-Host '[6] Save Exclusions & Back to Menu'
        Write-Host '==================================================' -ForegroundColor Cyan
        $choice = Read-Host 'Selection'
        switch ($choice) {
            '1' { $Config.DryRunDefault = -not $Config.DryRunDefault }
            '2' { $Config.CreateRestorePoint = -not $Config.CreateRestorePoint }
            '3' { $Config.ConfirmNuclearActions = -not $Config.ConfirmNuclearActions }
            '4' { $Config.EnableStorageSenseIntegration = -not $Config.EnableStorageSenseIntegration }
            '5' { 
                Write-Host 'Exclusions:'
                $Config.Exclusions | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }
                $null = Read-Host 'Press Enter to continue'
            }
            '6' { 
                Save-UscConfig -Config $Config -Path $script:ConfigPath
                Write-Host 'Settings saved successfully.' -ForegroundColor Green
                Start-Sleep -Seconds 1
                return
            }
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
        $certs = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue
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
    # Interactive TUI Loop
    while ($true) {
        $runId = Get-Date -Format 'yyyyMMdd-HHmmss'
        $script:Started = Get-Date
        $logFile = Initialize-UscLogger -LogDirectory $config.LogDirectory -RunId $runId
        
        # Re-read config in case settings were changed in config editor
        $config = Read-UscConfig -Path $script:ConfigPath
        $config.LogDirectory = [Environment]::ExpandEnvironmentVariables($config.LogDirectory)
        $config.ReportDirectory = [Environment]::ExpandEnvironmentVariables($config.ReportDirectory)
        $dryRun = [bool]($WhatIfOnly -or $config.DryRunDefault)

        $choice = Show-UscMenu -Config $config
        $mode = $choice.Mode
        if ($mode -eq 'Exit') { break }

        $confirmedNuke = $false
        if ($choice.ContainsKey('ConfirmNuclear')) {
            $confirmedNuke = [bool]$choice.ConfirmNuclear
        }

        Write-UscLog -Level Audit -Message 'Run started' -Data @{ Mode = $mode; WhatIfOnly = $dryRun; ConfigPath = $script:ConfigPath }
        $results = [System.Collections.Generic.List[object]]::new()

        try {
            switch ($mode) {
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
                        Write-Host " - $(Format-UscBytes -Bytes $_.Size) : $($_.Path)"
                    }
                    Write-Host '==================================================' -ForegroundColor Cyan
                    $results.Add((New-UscOperationResult -Name 'Deep Space Analysis' -Category Analyze -Status Succeeded -Message "Scanned $($deepScan.TotalInspectedFiles) files"))
                }
                'ComponentStore' { 
                    $analysis = Get-UscComponentStoreAnalysis
                    $results.Add((New-UscOperationResult -Name 'Component Store Analysis' -Category Analyze -Status Succeeded -Metadata @{ Analysis = $analysis })) 
                    Write-Host "Store Analysis Status: Cleanup recommended? $($analysis.RecommendedCleanup)" -ForegroundColor Yellow
                }
                default { 
                    $results.AddRange(@(Invoke-UscCleanupMode -Mode $mode -Config $config -WhatIfOnly:$dryRun -ConfirmNuclear:$confirmedNuke)) 
                }
            }
        }
        catch {
            Write-UscLog -Level Critical -Message 'Run failed' -Exception $_.Exception
            $results.Add((New-UscOperationResult -Name 'Run' -Category Clean -Status Failed -Message $_.Exception.Message))
        }

        $run = New-UscRunRecord -RunId $runId -Mode $mode -Results @($results) -Config $config -WhatIfOnly:$dryRun
        $reportPaths = [System.Collections.Generic.List[string]]::new()

        if ($GenerateReport -or $mode -in 'Analyze','DeepSpace','ComponentStore','Safe','Aggressive','Nuclear') {
            $reportPaths.Add((New-UscJsonReport -Run $run -OutputDirectory $config.ReportDirectory))
            $reportPaths.Add((New-UscCsvReport -Results @($results) -OutputDirectory $config.ReportDirectory -RunId $runId))
            $reportPaths.Add((New-UscHtmlReport -Run $run -OutputDirectory $config.ReportDirectory))
        }

        Write-UscLog -Level Audit -Message 'Run finished' -Data @{ Mode = $mode; TotalBytesFreed = $run.TotalBytesFreed; Reports = @($reportPaths); LogFile = $logFile }

        # Display summary to user
        Write-Host '==================================================' -ForegroundColor Cyan
        Write-Host '          ULTIMATE SYSTEM CLEANER SUMMARY         ' -ForegroundColor White -BackgroundColor Blue
        Write-Host '==================================================' -ForegroundColor Cyan
        Write-Host " Run Identifier : $runId"
        Write-Host " Mode Executed  : $mode"
        Write-Host " Dry Run Status : $dryRun"
        Write-Host " Total Freed    : $(Format-UscBytes -Bytes $run.TotalBytesFreed)" -ForegroundColor Green
        Write-Host " Log File Location: $logFile"
        Write-Host ' Reports Generated:'
        $reportPaths | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        Write-Host '==================================================' -ForegroundColor Cyan
        
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
    elseif ($Analyze) { $mode = 'Analyze' }
    elseif ($ComponentStore) { $mode = 'ComponentStore' }
    elseif ($InstallScheduledTask) { $mode = 'InstallScheduledTask' }
    elseif ($RemoveScheduledTask) { $mode = 'RemoveScheduledTask' }

    Write-UscLog -Level Audit -Message 'Run started' -Data @{ Mode = $mode; WhatIfOnly = $dryRun; ConfigPath = $script:ConfigPath }
    $results = [System.Collections.Generic.List[object]]::new()

    try {
        switch ($mode) {
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

    if ($GenerateReport -or $mode -in 'Analyze','Safe','Aggressive','Nuclear') {
        $reportPaths.Add((New-UscJsonReport -Run $run -OutputDirectory $config.ReportDirectory))
        $reportPaths.Add((New-UscCsvReport -Results @($results) -OutputDirectory $config.ReportDirectory -RunId $runId))
        $reportPaths.Add((New-UscHtmlReport -Run $run -OutputDirectory $config.ReportDirectory))
    }

    Write-UscLog -Level Audit -Message 'Run finished' -Data @{ Mode = $mode; TotalBytesFreed = $run.TotalBytesFreed; Reports = @($reportPaths); LogFile = $logFile }

    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host '          ULTIMATE SYSTEM CLEANER SUMMARY         ' -ForegroundColor White -BackgroundColor Blue
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host " Run Identifier : $runId"
    Write-Host " Mode Executed  : $mode"
    Write-Host " Dry Run Status : $dryRun"
    Write-Host " Total Freed    : $(Format-UscBytes -Bytes $run.TotalBytesFreed)" -ForegroundColor Green
    Write-Host " Log File Location: $logFile"
    Write-Host ' Reports Generated:'
    $reportPaths | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host '==================================================' -ForegroundColor Cyan

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

