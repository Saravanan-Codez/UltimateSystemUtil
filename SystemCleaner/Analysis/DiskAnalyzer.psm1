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
        $allItems = Get-ChildItem -LiteralPath $RootPath -Force -Recurse -File -ErrorAction SilentlyContinue
        foreach ($item in $allItems) {
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                continue
            }

            $len = [Int64]$item.Length
            $name = $item.Name
            $ext = $item.Extension.ToLowerInvariant()
            $fullName = $item.FullName

            # Categorize size
            if ($fullName -match '(?i)\\Cache\\|\\DXCache|\\GLCache|\\browser|\\thumbcache_') {
                $categorySizes.Caches += $len
            }
            elseif ($ext -eq '.log' -or $fullName -match '(?i)\\Logs\\|\\WER\\') {
                $categorySizes.Logs += $len
            }
            elseif ($ext -in '.dmp', '.mdmp', '.hdmp' -or $fullName -match '(?i)\\CrashDumps\\|\\Minidump') {
                $categorySizes.Dumps += $len
            }
            elseif ($fullName -match '(?i)\\SoftwareDistribution\\|\\DeliveryOptimization') {
                $categorySizes.Updates += $len
            }
            else {
                $categorySizes.SystemOther += $len
            }

            $filesList.Add([pscustomobject]@{
                Path = $fullName
                Size = $len
            })
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

    $sumPath = {
        param([string[]]$paths)
        $total = 0L
        foreach ($path in $paths) {
            if (Test-Path -LiteralPath $path) {
                $files = Get-ChildItem -LiteralPath $path -Force -Recurse -File -ErrorAction SilentlyContinue
                foreach ($f in $files) {
                    $total += $f.Length
                }
            }
        }
        return $total
    }
    
    $tempSize = &$sumPath $safePaths
    
    $recycleBinSize = 0L
    $drives = Get-UscDriveSnapshot
    foreach ($d in $drives) {
        $rbPath = Join-Path $d.Drive '$Recycle.Bin'
        if (Test-Path -LiteralPath $rbPath) {
            $files = Get-ChildItem -LiteralPath $rbPath -Force -Recurse -File -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $recycleBinSize += $f.Length
            }
        }
    }
    
    $werSize = &$sumPath $werPaths
    $gpuSize = &$sumPath $gpuPaths
    $updateSize = &$sumPath $updatePaths
    $browserSize = &$sumPath $browserPaths
    $dumpSize = &$sumPath $dumpPaths
    
    $sxsSize = 0L
    $sxsTempPath = Join-Path $env:WINDIR 'WinSxS\Temp'
    if (Test-Path -LiteralPath $sxsTempPath) {
        $files = Get-ChildItem -LiteralPath $sxsTempPath -Force -Recurse -File -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $sxsSize += $f.Length
        }
    }
    if (Test-Path -LiteralPath (Join-Path $env:WINDIR 'WinSxS')) {
        $sxsSize += 850MB
    }

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

