Set-StrictMode -Version Latest

function Get-UscDriveSnapshot {
    [CmdletBinding()]
    param([string[]]$DriveLetter = @())

    $volumes = if ($DriveLetter -and $DriveLetter.Count -gt 0) {
        foreach ($drive in $DriveLetter) {
            $normalized = $drive.TrimEnd(':').TrimEnd('\')
            $deviceId = ('{0}:' -f $normalized)
            Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$deviceId'" -ErrorAction SilentlyContinue
        }
    } else {
        Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    }

    foreach ($volume in $volumes) {
        if (-not $volume) { continue }
        [pscustomobject]@{
            Drive       = $volume.DeviceID
            VolumeName  = $volume.VolumeName
            FileSystem  = $volume.FileSystem
            Size        = [Int64]$volume.Size
            FreeSpace   = [Int64]$volume.FreeSpace
            UsedSpace   = [Int64]($volume.Size - $volume.FreeSpace)
            PercentFree = if ($volume.Size) { [Math]::Round(($volume.FreeSpace / $volume.Size) * 100, 2) } else { 0 }
            Timestamp   = Get-Date
        }
    }
}

function Get-UscDirectorySize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$Depth = 1
    )

    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    $root = Get-Item -LiteralPath $Path -Force
    $children = @(if ($Depth -le 0) { $root } else { Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue })
    
    $results = [System.Collections.Generic.List[object]]::new()
    
    foreach ($child in $children) {
        # Prevent junction point / symlink loops
        if ($child.PSIsContainer -and ($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            Write-UscLog -Level Debug -Message "Skipped reparse point (junction/symlink) at $($child.FullName)"
            continue
        }

        $size = 0L
        try {
            if ($child.PSIsContainer) {
                # Recursively sum sizes while omitting sub-junctions
                $subItems = Get-ChildItem -LiteralPath $child.FullName -Force -Recurse -ErrorAction SilentlyContinue
                foreach ($sub in $subItems) {
                    if ($sub.PSIsContainer) {
                        # Skip directory objects themselves
                        continue
                    }
                    if ($sub.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                        # Skip nested junctions/reparse points
                        continue
                    }
                    if ($sub.Length) {
                        $size += [Int64]$sub.Length
                    }
                }
            }
            else {
                $size = [Int64]$child.Length
            }
        }
        catch {
            Write-UscLog -Level Warning -Message "Unable to size $($child.FullName)" -Exception $_.Exception
        }

        $results.Add([pscustomobject]@{
            Path      = $child.FullName
            Name      = $child.Name
            IsFolder  = [bool]$child.PSIsContainer
            Bytes     = $size
            Timestamp = Get-Date
        })
    }
    return @($results)
}

function Get-UscCleanupOpportunity {
    [CmdletBinding()]
    param([psobject]$Config)

    $candidatePaths = @(
        $env:TEMP,
        (Join-Path $env:WINDIR 'Temp'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER'),
        (Join-Path $env:WINDIR 'SoftwareDistribution\Download')
    )

    $results = [System.Collections.Generic.List[object]]::new()
    
    foreach ($path in $candidatePaths | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        
        $items = @()
        try {
            $rawItems = Get-ChildItem -LiteralPath $path -Force -Recurse -ErrorAction SilentlyContinue
            $items = @($rawItems | Where-Object { 
                -not $_.PSIsContainer -and 
                -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and
                -not (Test-UscExcludedPath -Path $_.FullName -Exclusions $Config.Exclusions) 
            })
        }
        catch {
            Write-UscLog -Level Warning -Message "Could not inspect paths under $path" -Exception $_.Exception
        }
        
        $size = Measure-UscObjectSum -InputObject $items -Property Length
        $results.Add([pscustomobject]@{
            Path = $path
            Files = $items.Count
            Bytes = [Int64]$size
        })
    }
    return @($results)
}

function Get-UscDeepSpaceAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [int]$MaxItems = 10
    )

    if (-not (Test-Path -LiteralPath $RootPath)) {
        return @()
    }
    Write-UscLog -Level Information -Message "Starting deep disk space scan of $RootPath"
    
    $filesList = [System.Collections.Generic.List[object]]::new()
    $categorySizes = @{
        Caches      = 0L
        Logs        = 0L
        Dumps       = 0L
        Updates     = 0L
        SystemOther = 0L
    }

    try {
        # 1. Scan root files in the main thread (very fast)
        $rootFiles = Get-ChildItem -LiteralPath $RootPath -File -Force -ErrorAction SilentlyContinue
        foreach ($item in $rootFiles) {
            $len = [Int64]$item.Length
            $ext = $item.Extension.ToLowerInvariant()
            $fullName = $item.FullName

            if ($fullName -match '(?i)\\Cache\\|\\DXCache|\\GLCache|\\browser|\\thumbcache_') { $categorySizes.Caches += $len }
            elseif ($ext -eq '.log' -or $fullName -match '(?i)\\Logs\\|\\WER\\') { $categorySizes.Logs += $len }
            elseif ($ext -in '.dmp', '.mdmp', '.hdmp' -or $fullName -match '(?i)\\CrashDumps\\|\\Minidump') { $categorySizes.Dumps += $len }
            elseif ($fullName -match '(?i)\\SoftwareDistribution\\|\\DeliveryOptimization') { $categorySizes.Updates += $len }
            else { $categorySizes.SystemOther += $len }

            $filesList.Add([pscustomobject]@{ Path = $fullName; Size = $len })
        }

        # 2. Get all top-level directories to scan in parallel
        $subDirs = Get-ChildItem -LiteralPath $RootPath -Directory -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        
        $scriptBlock = {
            param($dir)
            $subFiles = [System.Collections.Generic.List[object]]::new()
            $subCats = @{ Caches = 0L; Logs = 0L; Dumps = 0L; Updates = 0L; SystemOther = 0L }

            $allItems = Get-ChildItem -LiteralPath $dir -Force -Recurse -File -ErrorAction SilentlyContinue
            foreach ($item in $allItems) {
                if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
                $len = [Int64]$item.Length
                $ext = $item.Extension.ToLowerInvariant()
                $fullName = $item.FullName

                if ($fullName -match '(?i)\\Cache\\|\\DXCache|\\GLCache|\\browser|\\thumbcache_') { $subCats.Caches += $len }
                elseif ($ext -eq '.log' -or $fullName -match '(?i)\\Logs\\|\\WER\\') { $subCats.Logs += $len }
                elseif ($ext -in '.dmp', '.mdmp', '.hdmp' -or $fullName -match '(?i)\\CrashDumps\\|\\Minidump') { $subCats.Dumps += $len }
                elseif ($fullName -match '(?i)\\SoftwareDistribution\\|\\DeliveryOptimization') { $subCats.Updates += $len }
                else { $subCats.SystemOther += $len }

                $subFiles.Add([pscustomobject]@{ Path = $fullName; Size = $len })
            }
            return [pscustomobject]@{ Files = $subFiles; Categories = $subCats }
        }

        $runspaceManagerPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Core\RunspaceManager.psm1"
        if (Test-Path $runspaceManagerPath) {
            Import-Module $runspaceManagerPath -ErrorAction SilentlyContinue
        }

        if (Get-Command Invoke-UscParallel -ErrorAction SilentlyContinue) {
            $scanResults = Invoke-UscParallel -InputObject $subDirs -ScriptBlock $scriptBlock -ThrottleLimit 8
            foreach ($res in $scanResults) {
                if ($res.Files) { $filesList.AddRange($res.Files) }
                if ($res.Categories) {
                    $categorySizes.Caches += $res.Categories.Caches
                    $categorySizes.Logs += $res.Categories.Logs
                    $categorySizes.Dumps += $res.Categories.Dumps
                    $categorySizes.Updates += $res.Categories.Updates
                    $categorySizes.SystemOther += $res.Categories.SystemOther
                }
            }
        } else {
            # Fallback to sequential scanning if parallel executor could not load
            foreach ($dir in $subDirs) {
                $res = & $scriptBlock -dir $dir
                if ($res.Files) { $filesList.AddRange($res.Files) }
                $categorySizes.Caches += $res.Categories.Caches
                $categorySizes.Logs += $res.Categories.Logs
                $categorySizes.Dumps += $res.Categories.Dumps
                $categorySizes.Updates += $res.Categories.Updates
                $categorySizes.SystemOther += $res.Categories.SystemOther
            }
        }
    }
    catch {
        Write-UscLog -Level Error -Message "Deep scan failed on $RootPath" -Exception $_.Exception
    }

    $topFiles = $filesList | Sort-Object Size -Descending | Select-Object -First $MaxItems

    return [pscustomobject]@{
        RootPath      = $RootPath
        Categories    = $categorySizes
        TopFiles      = @($topFiles)
        TotalInspectedFiles = $filesList.Count
    }
}

function Get-UscDiagnosisEstimate {
    [CmdletBinding()]
    param([psobject]$Config)

    $safePaths = @(
        $env:TEMP,
        (Join-Path $env:WINDIR 'Temp')
    )
    
    $werPaths = @(
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER')
    )
    
    $gpuPaths = @(
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Shader Cache'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Shader Cache')
    )
    if ($env:LOCALAPPDATA) {
        $gpuPaths += @(
            (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache'),
            (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'),
            (Join-Path $env:LOCALAPPDATA 'NVIDIACorp\PlayFiles')
        ) | Where-Object { $_ }
    }
    
    $updatePaths = @(
        (Join-Path $env:WINDIR 'SoftwareDistribution\Download'),
        (Join-Path $env:ProgramData 'Microsoft\Network\Downloader')
    )
    
    $dumpPaths = @(
        (Join-Path $env:WINDIR 'Minidump'),
        (Join-Path $env:WINDIR 'MEMORY.DMP'),
        (Join-Path $env:LOCALAPPDATA 'CrashDumps')
    )
    
    $browserPaths = @()
    if ($env:LOCALAPPDATA) {
        $browserPaths += @(
            (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache')
        )
    }
    $scanTargets = @(
        @{ Key = 'Temp'; Paths = $safePaths },
        @{ Key = 'RecycleBin'; Paths = $null; IsRecycle = $true },
        @{ Key = 'WER'; Paths = $werPaths },
        @{ Key = 'GpuShader'; Paths = $gpuPaths },
        @{ Key = 'WindowsUpdate'; Paths = $updatePaths },
        @{ Key = 'Browser'; Paths = $browserPaths },
        @{ Key = 'CrashDumps'; Paths = $dumpPaths },
        @{ Key = 'ComponentStore'; Paths = @(Join-Path $env:WINDIR 'WinSxS\Temp'); IsSxS = $true }
    )

    $scriptBlock = {
        param($target)
        $total = 0L
        if ($target.IsRecycle) {
            $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
            foreach ($d in $drives) {
                $rbPath = Join-Path $d.DeviceID '$Recycle.Bin'
                if (Test-Path -LiteralPath $rbPath) {
                    $files = Get-ChildItem -LiteralPath $rbPath -Force -Recurse -File -ErrorAction SilentlyContinue
                    foreach ($f in $files) {
                        $total += [Int64]$f.Length
                    }
                }
            }
        }
        elseif ($target.IsSxS) {
            $sxsTempPath = $target.Paths[0]
            if (Test-Path -LiteralPath $sxsTempPath) {
                $files = Get-ChildItem -LiteralPath $sxsTempPath -Force -Recurse -File -ErrorAction SilentlyContinue
                foreach ($f in $files) {
                    $total += [Int64]$f.Length
                }
            }
            if (Test-Path -LiteralPath (Join-Path $env:windir 'WinSxS')) {
                $total += 891289600L # 850MB
            }
        }
        else {
            foreach ($path in $target.Paths) {
                if (Test-Path -LiteralPath $path) {
                    $files = Get-ChildItem -LiteralPath $path -Force -Recurse -File -ErrorAction SilentlyContinue
                    foreach ($f in $files) {
                        $total += [Int64]$f.Length
                    }
                }
            }
        }
        return [pscustomobject]@{ Key = $target.Key; Size = $total }
    }

    $runspaceManagerPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Core\RunspaceManager.psm1"
    if (Test-Path $runspaceManagerPath) {
        Import-Module $runspaceManagerPath -ErrorAction SilentlyContinue
    }

    $sizes = @{}
    if (Get-Command Invoke-UscParallel -ErrorAction SilentlyContinue) {
        $scanResults = Invoke-UscParallel -InputObject $scanTargets -ScriptBlock $scriptBlock -ThrottleLimit 8
        foreach ($res in $scanResults) {
            $sizes[$res.Key] = $res.Size
        }
    } else {
        # Fallback to sequential scanning if RunspaceManager failed to load
        foreach ($target in $scanTargets) {
            $size = & $scriptBlock -target $target
            $sizes[$target.Key] = $size.Size
        }
    }

    $tempSize = if ($sizes.ContainsKey('Temp')) { $sizes['Temp'] } else { 0L }
    $recycleBinSize = if ($sizes.ContainsKey('RecycleBin')) { $sizes['RecycleBin'] } else { 0L }
    $werSize = if ($sizes.ContainsKey('WER')) { $sizes['WER'] } else { 0L }
    $gpuSize = if ($sizes.ContainsKey('GpuShader')) { $sizes['GpuShader'] } else { 0L }
    $updateSize = if ($sizes.ContainsKey('WindowsUpdate')) { $sizes['WindowsUpdate'] } else { 0L }
    $browserSize = if ($sizes.ContainsKey('Browser')) { $sizes['Browser'] } else { 0L }
    $dumpSize = if ($sizes.ContainsKey('CrashDumps')) { $sizes['CrashDumps'] } else { 0L }
    $sxsSize = if ($sizes.ContainsKey('ComponentStore')) { $sizes['ComponentStore'] } else { 0L }

    $safeTotal = $tempSize + $recycleBinSize
    $aggressiveTotal = $safeTotal + $werSize + $gpuSize + $updateSize + $browserSize
    $nuclearTotal = $aggressiveTotal + $dumpSize + $sxsSize
    
    return [pscustomobject]@{
        Safe = $safeTotal
        Aggressive = $aggressiveTotal
        Nuclear = $nuclearTotal
        Breakdown = @{
            Temp = $tempSize
            RecycleBin = $recycleBinSize
            WER = $werSize
            GpuShader = $gpuSize
            WindowsUpdate = $updateSize
            Browser = $browserSize
            CrashDumps = $dumpSize
            ComponentStore = $sxsSize
        }
    }
}

Export-ModuleMember -Function Get-UscDriveSnapshot, Get-UscDirectorySize, Get-UscCleanupOpportunity, Get-UscDeepSpaceAnalysis, Get-UscDiagnosisEstimate

