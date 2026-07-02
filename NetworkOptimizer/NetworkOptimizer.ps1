[CmdletBinding()]
param(
    [switch]$Menu
)

$ErrorActionPreference = 'Stop'

function Show-NetworkHeader {
    Clear-Host
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host '         FALKON NETWORK OPTIMIZER                 ' -ForegroundColor White -BackgroundColor DarkMagenta
    Write-Host '==================================================' -ForegroundColor Cyan
}

function Invoke-TcpOptimization {
    Write-Host "[*] Applying TCP/IP Optimization (Nagle's Algorithm & TCPNoDelay)..." -ForegroundColor Yellow
    
    # TCP NoDelay and TcpAckFrequency (Nagle's Algorithm disable for gaming)
    $interfaces = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\*" -ErrorAction SilentlyContinue
    foreach ($iface in $interfaces) {
        $path = $iface.PSPath
        Set-ItemProperty -Path $path -Name "TcpAckFrequency" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $path -Name "TCPNoDelay" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    }
    
    # Global TCP Settings
    netsh int tcp set global autotuninglevel=normal | Out-Null
    netsh int tcp set global ecncapability=disabled | Out-Null
    netsh int tcp set heuristics disabled | Out-Null
    
    Write-Host "[+] TCP/IP Stack Optimized." -ForegroundColor Green
    Start-Sleep -Seconds 1
}

function Invoke-DnsFlush {
    Write-Host "[*] Flushing DNS Cache and Resetting Winsock..." -ForegroundColor Yellow
    ipconfig /flushdns | Out-Null
    netsh winsock reset | Out-Null
    Write-Host "[+] DNS Flushed." -ForegroundColor Green
    Start-Sleep -Seconds 1
}

function Invoke-DisableDeliveryOptimization {
    Write-Host "[*] Disabling P2P Windows Update Delivery Optimization..." -ForegroundColor Yellow
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Write-Host "[+] Bandwidth Hogging Disabled." -ForegroundColor Green
    Start-Sleep -Seconds 1
}

if ($Menu) {
    while ($true) {
        Show-NetworkHeader
        Write-Host "Select Network Action:" -ForegroundColor Yellow
        Write-Host "--------------------------------------------------" -ForegroundColor Cyan
        Write-Host "[1] Apply Ultimate Network Profile (Gaming & Streaming)" -ForegroundColor Green
        Write-Host "[0] Back to Main Menu" -ForegroundColor White
        Write-Host "==================================================" -ForegroundColor Cyan
        
        $choice = Read-Host "Selection"
        if ($choice -eq '0') { return }
        if ($choice -eq '1') {
            Show-NetworkHeader
            Invoke-TcpOptimization
            Invoke-DnsFlush
            Invoke-DisableDeliveryOptimization
            
            Write-Host "==================================================" -ForegroundColor Cyan
            Write-Host "Network Optimization Complete! A system reboot is recommended." -ForegroundColor Green
            Write-Host "Press any key to return..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
}
