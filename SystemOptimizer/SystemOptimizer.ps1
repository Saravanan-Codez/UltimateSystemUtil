[CmdletBinding()]
param(
    [switch]$Menu
)

$ErrorActionPreference = 'Stop'

function Show-OptimizerHeader {
    Clear-Host
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host '         FALKON SYSTEM OPTIMIZER (TWEAKER)        ' -ForegroundColor White -BackgroundColor DarkMagenta
    Write-Host '==================================================' -ForegroundColor Cyan
}

function Invoke-TelemetryNuke {
    Write-Host "[*] Nuking Telemetry & Data Collection..." -ForegroundColor Yellow
    # Disable DiagTrack
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Stop-Service "DiagTrack" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    Set-Service "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
    # Disable WAP Push
    Stop-Service "dmwappushservice" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    Set-Service "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host "[+] Telemetry Nuked successfully." -ForegroundColor Green
    Start-Sleep -Seconds 1
}

function Invoke-Debloat {
    param([string]$Profile)
    Write-Host "[*] Eradicating Bloatware ($Profile Profile)..." -ForegroundColor Yellow
    
    $commonBloat = @(
        "*Microsoft.BingNews*",
        "*Microsoft.GetHelp*",
        "*Microsoft.Getstarted*",
        "*Microsoft.Microsoft3DViewer*",
        "*Microsoft.MicrosoftSolitaireCollection*",
        "*Microsoft.WindowsFeedbackHub*",
        "*Microsoft.ZuneVideo*",
        "*king.com.CandyCrush*"
    )
    
    if ($Profile -eq 'Performance') {
        # Keep Xbox stuff, remove Office Hub
        $commonBloat += "*Microsoft.MicrosoftOfficeHub*"
    }
    elseif ($Profile -eq 'Stability') {
        # Keep Office, remove Xbox stuff
        $commonBloat += "*Microsoft.XboxApp*"
        $commonBloat += "*Microsoft.XboxGamingOverlay*"
        $commonBloat += "*Microsoft.XboxIdentityProvider*"
    }
    
    foreach ($app in $commonBloat) {
        Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    }
    Write-Host "[+] Bloatware Eradicated." -ForegroundColor Green
    Start-Sleep -Seconds 1
}

function Invoke-ServicesTweaks {
    param([string]$Profile)
    Write-Host "[*] Optimizing Services ($Profile Profile)..." -ForegroundColor Yellow
    
    # Disable Superfetch/SysMain (good for SSDs)
    Stop-Service "SysMain" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    Set-Service "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue
    
    if ($Profile -eq 'Performance') {
        # Disable Windows Search indexing for max disk performance
        Stop-Service "WSearch" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Set-Service "WSearch" -StartupType Disabled -ErrorAction SilentlyContinue
    }
    Write-Host "[+] Services Optimized." -ForegroundColor Green
    Start-Sleep -Seconds 1
}

if ($Menu) {
    while ($true) {
        Show-OptimizerHeader
        Write-Host "Select your Optimization Profile:" -ForegroundColor Yellow
        Write-Host "--------------------------------------------------" -ForegroundColor Cyan
        Write-Host "[1] Maximum Performance (Lowest latency, Removes built-in productivity apps)" -ForegroundColor Green
        Write-Host "[2] Maximum Stability & Productivity (Safe tweaks, Keeps productivity apps)" -ForegroundColor Blue
        Write-Host "[0] Back to Main Menu" -ForegroundColor White
        Write-Host "==================================================" -ForegroundColor Cyan
        
        $choice = Read-Host "Profile Selection"
        $profile = ''
        switch ($choice) {
            '1' { $profile = 'Performance' }
            '2' { $profile = 'Stability' }
            '0' { return }
            default { continue }
        }
        
        Show-OptimizerHeader
        Write-Host "Applying $profile Tweaks. Please wait..." -ForegroundColor Cyan
        Invoke-TelemetryNuke
        Invoke-Debloat -Profile $profile
        Invoke-ServicesTweaks -Profile $profile
        
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host "Optimization Complete! A system reboot is recommended." -ForegroundColor Green
        Write-Host "Press any key to return..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}
