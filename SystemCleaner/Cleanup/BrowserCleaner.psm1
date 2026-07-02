Set-StrictMode -Version Latest

function Get-UscInstalledBrowsers {
    [CmdletBinding()]
    param()

    # Registry locations for installed browsers
    $registryPaths = @(
        'HKLM:\SOFTWARE\Clients\StartMenuInternet',
        'HKCU:\SOFTWARE\Clients\StartMenuInternet'
    )
    
    $browsers = [System.Collections.Generic.List[string]]::new()
    foreach ($regPath in $registryPaths) {
        if (Test-Path -LiteralPath $regPath) {
            $keys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                $name = $key.PSChildName
                if ($name -notin $browsers) {
                    $browsers.Add($name)
                }
            }
        }
    }
    return @($browsers)
}

function Get-UscBrowserCacheTargets {
    [CmdletBinding()]
    param()

    # Output list of targets with Name, Path (profile base), and CacheSubPaths
    $targets = [System.Collections.Generic.List[hashtable]]::new()
    
    # Chromium based paths
    $chromiumApps = @(
        @{ Name = 'Google Chrome'; DirName = 'Google\Chrome\User Data' },
        @{ Name = 'Microsoft Edge'; DirName = 'Microsoft\Edge\User Data' },
        @{ Name = 'Brave Browser'; DirName = 'BraveSoftware\Brave-Browser\User Data' },
        @{ Name = 'Vivaldi Browser'; DirName = 'Vivaldi\User Data' },
        @{ Name = 'Opera Browser'; DirName = 'Opera Software\Opera Stable' }
    )

    foreach ($app in $chromiumApps) {
        $basePath = Join-Path $env:LOCALAPPDATA $app.DirName
        if (Test-Path -LiteralPath $basePath) {
            # Chromium browsers can have multiple profiles (Default, Profile 1, Profile 2, etc.)
            $profiles = @()
            if ($app.Name -eq 'Opera Browser') {
                # Opera structures differently
                $profiles = @($basePath)
            }
            else {
                # Find profile directories
                $profiles = @(Get-ChildItem -LiteralPath $basePath -Directory -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } |
                    Select-Object -ExpandProperty FullName)
            }

            foreach ($profile in $profiles) {
                $targets.Add(@{
                    Name = "$($app.Name) ($($profile | Split-Path -Leaf))"
                    Path = $profile
                    SubDirs = @(
                        'Cache\Cache_Data',
                        'Code Cache',
                        'GPUCache',
                        'Service Worker\CacheStorage',
                        'Service Worker\ScriptCache',
                        'Storage\ext'
                    )
                })
            }
        }
    }

    # Firefox paths
    $firefoxBase = Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'
    if (Test-Path -LiteralPath $firefoxBase) {
        $ffProfiles = @(Get-ChildItem -LiteralPath $firefoxBase -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        foreach ($ffProfile in $ffProfiles) {
            $targets.Add(@{
                Name = "Mozilla Firefox ($($ffProfile | Split-Path -Leaf))"
                Path = $ffProfile
                SubDirs = @(
                    'cache2',
                    'startupCache',
                    'jumpListCache',
                    'entries',
                    'thumbnail'
                )
            })
        }
    }

    return @($targets)
}

function Invoke-UscBrowserCacheCleanup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][psobject]$Config,
        [switch]$WhatIfOnly
    )

    $results = [System.Collections.Generic.List[object]]::new()
    
    # Check if browsers are running
    $browserProcesses = @('chrome', 'msedge', 'brave', 'firefox', 'opera', 'vivaldi')
    $runningBrowsers = @()
    foreach ($proc in $browserProcesses) {
        if (Get-Process -Name $proc -ErrorAction SilentlyContinue) {
            $runningBrowsers += $proc
        }
    }

    if ($runningBrowsers.Count -gt 0 -and -not $WhatIfOnly) {
        Write-UscLog -Level Warning -Message "Active browser processes detected: $($runningBrowsers -join ', ')."
        if ($Host.UI -ne $null -and ($Host.Name -eq 'ConsoleHost' -or $Host.Name -eq 'Visual Studio Code Host')) {
            Write-Host "[!] WARNING: Active browser processes detected ($($runningBrowsers -join ', '))." -ForegroundColor Yellow
            $closePrompt = Read-Host "Would you like to close these browsers to ensure complete cache deletion? (y/N)"
            if ($closePrompt -match '^[yY]') {
                foreach ($proc in $runningBrowsers) {
                    Write-Host "[*] Stopping $proc process..." -ForegroundColor Gray
                    Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
                }
                Start-Sleep -Seconds 2
            } else {
                Write-Host "[*] Proceeding anyway. Note that locked files will be skipped." -ForegroundColor Gray
            }
        }
    }

    $targets = Get-UscBrowserCacheTargets
    foreach ($target in $targets) {
        $pathsToScan = [System.Collections.Generic.List[string]]::new()
        foreach ($sub in $target.SubDirs) {
            $fullSub = Join-Path $target.Path $sub
            if (Test-Path -LiteralPath $fullSub) {
                $pathsToScan.Add($fullSub)
            }
        }

        if ($pathsToScan.Count -eq 0) {
            $results.Add((New-UscOperationResult -Name $target.Name -Category Clean -Status Skipped -Message 'No cache directories exist' -Paths @($target.Path)))
            continue
        }

        # Gather files
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($scanPath in $pathsToScan) {
            $rawFiles = Get-ChildItem -LiteralPath $scanPath -File -Force -Recurse -ErrorAction SilentlyContinue
            foreach ($file in $rawFiles) {
                if (-not (Test-UscExcludedPath -Path $file.FullName -Exclusions $Config.Exclusions)) {
                    $items.Add($file)
                }
            }
        }

        $size = Measure-UscObjectSum -InputObject $items.ToArray() -Property Length
        $removed = 0
        $failed = 0

        foreach ($item in $items) {
            try {
                if ($WhatIfOnly) { 
                    $removed += [Int64]$item.Length
                    continue 
                }
                
                if ($PSCmdlet.ShouldProcess($item.FullName, "Remove browser cache ($($target.Name))")) {
                    $length = [Int64]$item.Length
                    Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                    $removed += $length
                }
            }
            catch {
                $failed++
                Write-UscLog -Level Debug -Message "Browser cache item locked: $($item.FullName)"
            }
        }

        # Try to clean empty folders under target paths
        if (-not $WhatIfOnly) {
            foreach ($scanPath in $pathsToScan) {
                $subDirs = Get-ChildItem -LiteralPath $scanPath -Directory -Force -Recurse -ErrorAction SilentlyContinue |
                    Sort-Object { $_.FullName.Length } -Descending
                foreach ($dir in $subDirs) {
                    try {
                        $contents = @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue)
                        if ($contents.Count -eq 0) {
                            Remove-Item -LiteralPath $dir.FullName -Force -ErrorAction Stop
                        }
                    }
                    catch {}
                }
            }
        }

        $status = if ($failed -gt 0 -and $removed -gt 0) { 'PartiallySucceeded' } elseif ($failed -gt 0) { 'Failed' } else { 'Succeeded' }
        $results.Add((New-UscOperationResult -Name $target.Name -Category Clean -Status $status -BytesBefore $size -BytesFreed $removed -Paths $pathsToScan.ToArray() -Message "$($items.Count) files inspected, $failed locked items skipped"))
    }
    return @($results)
}

Export-ModuleMember -Function Get-UscBrowserCacheTargets, Invoke-UscBrowserCacheCleanup, Get-UscInstalledBrowsers

