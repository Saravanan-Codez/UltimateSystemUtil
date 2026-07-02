# Falkon System Utilities (FalkonSysUtils) - The Holy Grail Update

A profound, production-grade PowerShell utility suite for extreme Windows optimization, debloat, and maintenance. Tailored for both high-performance gaming and stable enterprise environments.

## Feature Modules

- **Falkon System Cleaner**: Advanced disk space recovery featuring Safe, Aggressive, and Nuclear modes (with Windows Update cache and Component Store resetbase capabilities).
- **Falkon System Optimizer (Tweaker)**: Automatically nukes telemetry, removes stubborn bloatware (Candy Crush, Xbox overlays, etc.), and disables heavy services (Superfetch/SysMain on SSDs) based on your selected profile (Maximum Performance vs. Maximum Stability).
- **Falkon Network Optimizer**: Modifies the TCP/IP stack to lower network latency (disables Nagle's Algorithm via TCPNoDelay), resets Winsock, and halts bandwidth-hogging Delivery Optimization (P2P Windows Updates).
- **Falkon Registry Optimizer**: Restores the classic Windows 10 context menu (bypassing the slow 'Show more options' delay) and injects `Win32PrioritySeparation` tweaks to prioritize foreground task processing.

---

## Quick Start

### Web Installer (Direct In-Memory Load)
Run the following in an elevated PowerShell session to download, extract, and start the dynamic interactive dashboard:
```powershell
irm https://raw.githubusercontent.com/Saravanan-Codez/FalkonSysUtils/main/FalkonSysUtils.ps1 | iex
```

### Local CLI Execution
Clone or extract the ZIP locally and invoke the root orchestrator:
```powershell
# Launch interactive TUI suite
.\FalkonSysUtils.ps1

# Direct CLI pass-through to System Cleaner
.\FalkonSysUtils.ps1 -Analyze
.\FalkonSysUtils.ps1 -Safe -GenerateReport
```

---

## Dynamic Dashboard
The main orchestrator (`FalkonSysUtils.ps1`) automatically queries WMI/CIM objects on boot to display your current OS System, Processor model, and installed RAM capacity in real-time above the module selection menu.
