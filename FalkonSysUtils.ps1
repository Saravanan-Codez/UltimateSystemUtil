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

# Unblock downloaded script files to support manual ZIP downloads
Get-ChildItem -LiteralPath $PSScriptRoot -Include *.ps1,*.psm1 -Recurse -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Function to check Administrator context
function Test-UscAdministratorPrivilege {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-UscLogo {
    Write-Host '                 ___' -ForegroundColor Magenta
    Write-Host '     \          /   \       ___  _   _     _  __  ___   _   _' -ForegroundColor Magenta
    Write-Host '  ====\        /     \     | __|/ \ | |   | |/ / /   \ | \ | |' -ForegroundColor Magenta
    Write-Host ' ======\______/   _   \    | _|/ _ \| |__ |   <  | () | |  \| |' -ForegroundColor DarkMagenta
    Write-Host ' =======_        //\   >   |_|/_/ \_\____||_|\_\ \___/ |_|\___|' -ForegroundColor DarkMagenta
    Write-Host '  ======/       //  \_/    F A L K O N   S Y S   U T I L S' -ForegroundColor Cyan
    Write-Host '    ===/_______//' -ForegroundColor Cyan
    Write-Host '==================================================' -ForegroundColor Cyan
}

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
    Clear-Host
    Show-UscLogo
    Write-Host " Privilege Context : $adminStatus" -ForegroundColor Yellow
    Write-Host " OS System         : $osInfo" -ForegroundColor Gray
    Write-Host " Processor         : $cpuInfo" -ForegroundColor Gray
    Write-Host " Installed RAM     : $ramInfo GB" -ForegroundColor Gray
    Write-Host '--------------------------------------------------' -ForegroundColor Cyan
    Write-Host '[1] Run Falkon System Cleaner' -ForegroundColor Green
    Write-Host '[2] Falkon Registry Optimizer' -ForegroundColor Magenta
    Write-Host '[3] Falkon Network Optimizer' -ForegroundColor Blue
    Write-Host '[4] Falkon System Optimizer (Tweaker)' -ForegroundColor Yellow
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
