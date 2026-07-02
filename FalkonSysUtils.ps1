<# 
.SYNOPSIS
Ultimate System Utility - Production-Grade Windows Performance Suite
.DESCRIPTION
The root orchestrator and entry point for Falkon Labs Ultimate System Utility suite.
Features web-bootstrapping and coordinates multiple sub-tools (Cleaner, Optimizer, etc.).
.EXAMPLE
.\UltimateSystemUtil.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # System Cleaner Parameters (Forwarded to Cleaner launcher)
    [switch]$Safe,
    [switch]$Aggressive,
    [switch]$Nuclear,
    [switch]$Analyze,
    [switch]$ComponentStore,
    [switch]$InstallScheduledTask,
    [switch]$RemoveScheduledTask,
    [switch]$Menu,
    [switch]$GenerateReport,
    [switch]$WhatIfOnly,
    [switch]$ConfirmNuclear,
    [string]$ConfigPath
)

# --- Web Bootstrap Handler ---
if ([string]::IsNullOrEmpty($PSScriptRoot)) {
    $null = Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host '       FALKON SYSTEM UTILITIES WEB BOOTSTRAP       ' -ForegroundColor White -BackgroundColor Blue
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
            $launcherPath = Join-Path $expandedFolder.FullName 'FalkonSysUtils.ps1'
            Write-Host 'Running launcher in localized workspace...' -ForegroundColor Green
            Start-Sleep -Seconds 1
            
            $boundArgs = @{}
            foreach ($key in $PSBoundParameters.Keys) {
                $boundArgs[$key] = $PSBoundParameters[$key]
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

# Unblock downloaded script files to support manual ZIP downloads (excluding community Plugins)
Get-ChildItem -LiteralPath $PSScriptRoot -Include *.ps1,*.psm1 -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike "*\Plugins\*" } | Unblock-File -ErrorAction SilentlyContinue

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Function to check Administrator context
function Test-UscAdministratorPrivilege {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$corePath = Join-Path $PSScriptRoot 'Core\FalkonCore.psm1'
if (Test-Path -LiteralPath $corePath) { Import-Module $corePath -ErrorAction SilentlyContinue }

# Check if arguments are provided. If so, forward directly to System Cleaner CLI mode.
$argsBound = $PSBoundParameters.Count -gt 0
if ($argsBound -and -not $Menu) {
    $cleanerPath = Join-Path $PSScriptRoot 'SystemCleaner\UltimateSystemCleaner.ps1'
    if (Test-Path -LiteralPath $cleanerPath) {
        $boundArgs = @{}
        foreach ($key in $PSBoundParameters.Keys) {
            $boundArgs[$key] = $PSBoundParameters[$key]
        }
        & $cleanerPath @boundArgs
    }
    else {
        Write-Error "System Cleaner module is missing from $cleanerPath."
    }
    return
}

# Interactive TUI orchestrator loop
$adminStatus = 'Standard User (Some functions restricted)'
if (Test-UscAdministratorPrivilege) { $adminStatus = 'Elevated (Admin)' }

$osInfo = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
$cpuInfo = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name
$ramInfo = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB, 1)

while ($true) {
    if (Get-Command Show-FalkonLogo -ErrorAction SilentlyContinue) { Show-FalkonLogo } else { Clear-Host }
    Write-Host " Privilege Context : $adminStatus" -ForegroundColor Yellow
    Write-Host " OS System         : $osInfo" -ForegroundColor Gray
    Write-Host " Processor         : $cpuInfo" -ForegroundColor Gray
    Write-Host " Installed RAM     : $ramInfo GB" -ForegroundColor Gray
    Write-Host '--------------------------------------------------' -ForegroundColor Cyan
    Write-Host '[1] System Disk Space Cleaner' -ForegroundColor Green
    Write-Host '[2] Windows Registry Optimizer' -ForegroundColor Magenta
    Write-Host '[3] TCP/IP Network Connection Latency Optimizer' -ForegroundColor Blue
    Write-Host '[4] Windows Privacy Telemetry & Services Tweaker' -ForegroundColor Yellow
    Write-Host '[5] Software Silent Batch Package Installer' -ForegroundColor DarkCyan
    Write-Host '[6] Apply Recommended Settings (One-Click Preset)' -ForegroundColor Red
    Write-Host '[0] Exit' -ForegroundColor White
    Write-Host '==================================================' -ForegroundColor Cyan
    
    $selection = Read-Host 'Selection'
    switch ($selection) {
        '1' {
            $cleanerPath = Join-Path $PSScriptRoot 'SystemCleaner\UltimateSystemCleaner.ps1'
            if (Test-Path -LiteralPath $cleanerPath) { & $cleanerPath -Menu }
            else { Write-Host "Module missing: $cleanerPath" -ForegroundColor Red; Start-Sleep -Seconds 2 }
        }
        '2' {
            $regPath = Join-Path $PSScriptRoot 'RegistryOptimizer\RegistryOptimizer.ps1'
            if (Test-Path -LiteralPath $regPath) { & $regPath -Menu }
            else { Write-Host "Module missing: $regPath" -ForegroundColor Red; Start-Sleep -Seconds 2 }
        }
        '3' {
            $netPath = Join-Path $PSScriptRoot 'NetworkOptimizer\NetworkOptimizer.ps1'
            if (Test-Path -LiteralPath $netPath) { & $netPath -Menu }
            else { Write-Host "Module missing: $netPath" -ForegroundColor Red; Start-Sleep -Seconds 2 }
        }
        '4' {
            $optPath = Join-Path $PSScriptRoot 'SystemOptimizer\SystemOptimizer.ps1'
            if (Test-Path -LiteralPath $optPath) { & $optPath -Menu }
            else { Write-Host "Module missing: $optPath" -ForegroundColor Red; Start-Sleep -Seconds 2 }
        }
        '5' {
            $appPath = Join-Path $PSScriptRoot 'FalkonPackageStore\AppInstaller.ps1'
            if (Test-Path -LiteralPath $appPath) { & $appPath -Menu }
            else { Write-Host "Module missing: $appPath" -ForegroundColor Red; Start-Sleep -Seconds 2 }
        }
        '6' {
            if (Get-Command Show-FalkonLogo -ErrorAction SilentlyContinue) { Show-FalkonLogo -SubTitle "PRESET VERIFICATION" } else { Clear-Host }
            Write-Host "[!] WARNING: You are about to apply the Recommended Settings preset." -ForegroundColor Yellow
            Write-Host "This preset combines two distinct risk-level operations:" -ForegroundColor Gray
            Write-Host ""
            Write-Host " 1. Disk Cleanup (SAFE) - Deletes temp folders, recycle bin items, logs." -ForegroundColor Green
            Write-Host " 2. System Tweaks (INVASIVE) - Telemetry disable, network TCP tuning, registry optimizer." -ForegroundColor Red
            Write-Host ""
            $pConfirm = Read-Host "Are you sure you want to apply all recommended tweaks? (y/N)"
            if ($pConfirm -notmatch '^[yY]') {
                Write-Host "[*] Preset canceled." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                continue
            }

            if (Get-Command Show-FalkonLogo -ErrorAction SilentlyContinue) { Show-FalkonLogo -SubTitle "APPLYING PRESET" } else { Clear-Host }
            
            # 1. Safety Net Restore Point
            $safetyPath = Join-Path $PSScriptRoot "Safety\SystemRestore.psm1"
            if (Test-Path $safetyPath) {
                Import-Module $safetyPath -ErrorAction SilentlyContinue
                if (Get-Command Invoke-FalkonSafetyNet -ErrorAction SilentlyContinue) { Invoke-FalkonSafetyNet }
            }

            # 2. Disk Space Cleanup (Safe Mode)
            $cleanerPath = Join-Path $PSScriptRoot 'SystemCleaner\UltimateSystemCleaner.ps1'
            if (Test-Path $cleanerPath) {
                Write-Host "[*] Executing Safe Disk Cleanup..." -ForegroundColor Yellow
                & $cleanerPath -Safe -ErrorAction SilentlyContinue
            }

            # 3. Registry Optimizer
            $regPath = Join-Path $PSScriptRoot 'RegistryOptimizer\RegistryOptimizer.ps1'
            if (Test-Path $regPath) { & $regPath -Apply }

            # 4. Network Optimizer
            $netPath = Join-Path $PSScriptRoot 'NetworkOptimizer\NetworkOptimizer.ps1'
            if (Test-Path $netPath) { & $netPath -Apply }

            # 5. System Optimizer
            $optPath = Join-Path $PSScriptRoot 'SystemOptimizer\SystemOptimizer.ps1'
            if (Test-Path $optPath) { & $optPath -Apply }

            if (Get-Command Invoke-FalkonPause -ErrorAction SilentlyContinue) { Invoke-FalkonPause }
        }
        '0' {
            Write-Host 'Goodbye!' -ForegroundColor Cyan
            break
        }
        default {
            Write-Host 'Invalid choice, try again.' -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
