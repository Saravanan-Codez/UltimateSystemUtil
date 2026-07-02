[CmdletBinding()]
param(
    [switch]$Menu
)

$ErrorActionPreference = 'Stop'

function Show-RegistryHeader {
    Clear-Host
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host '         FALKON REGISTRY OPTIMIZER                ' -ForegroundColor White -BackgroundColor DarkMagenta
    Write-Host '==================================================' -ForegroundColor Cyan
}

function Invoke-ContextMenuFix {
    Write-Host "[*] Restoring Classic Windows 10 Context Menu (Removes 'Show more options')..." -ForegroundColor Yellow
    
    $path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    Set-ItemProperty -Path $path -Name "(Default)" -Value "" -ErrorAction SilentlyContinue
    
    Write-Host "[+] Context Menu Optimized." -ForegroundColor Green
    Start-Sleep -Seconds 1
}

function Invoke-PrioritySeparation {
    Write-Host "[*] Applying Win32PrioritySeparation (Foreground task latency bias)..." -ForegroundColor Yellow
    # Value 38 (0x26) gives foreground apps optimal priority over background tasks
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38 -Type DWord -ErrorAction SilentlyContinue
    Write-Host "[+] Win32PrioritySeparation Applied." -ForegroundColor Green
    Start-Sleep -Seconds 1
}

if ($Menu) {
    while ($true) {
        Show-RegistryHeader
        Write-Host "Select Registry Optimization Action:" -ForegroundColor Yellow
        Write-Host "--------------------------------------------------" -ForegroundColor Cyan
        Write-Host "[1] Apply Ultimate Registry Tweaks (Context Menu & Latency)" -ForegroundColor Green
        Write-Host "[0] Back to Main Menu" -ForegroundColor White
        Write-Host "==================================================" -ForegroundColor Cyan
        
        $choice = Read-Host "Selection"
        if ($choice -eq '0') { return }
        if ($choice -eq '1') {
            Show-RegistryHeader
            Invoke-ContextMenuFix
            Invoke-PrioritySeparation
            
            Write-Host "==================================================" -ForegroundColor Cyan
            Write-Host "Registry Optimization Complete! Please restart Explorer or reboot." -ForegroundColor Green
            Write-Host "Press any key to return..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
}
