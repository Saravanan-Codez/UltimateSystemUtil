Set-StrictMode -Version Latest

function Get-UscTempTargets {
    [CmdletBinding()]
    param([psobject]$Config)

    $targets = @(
        @{ Name = 'User Temp'; Path = $env:TEMP; Pattern = '*'; Recurse = $true },
        @{ Name = 'Windows Temp'; Path = Join-Path $env:WINDIR 'Temp'; Pattern = '*'; Recurse = $true },
        @{ Name = 'Prefetch'; Path = Join-Path $env:WINDIR 'Prefetch'; Pattern = '*.pf'; Recurse = $false },
        @{ Name = 'Cryptnet URL Cache'; Path = Join-Path $env:APPDATA 'Microsoft\CryptnetUrlCache'; Pattern = '*'; Recurse = $true },
        @{ Name = 'Windows Installer Temp'; Path = Join-Path $env:WINDIR 'Installer\$MSI*'; Pattern = '*'; Recurse = $true },
        @{ Name = 'CBS and DISM Logs'; Path = Join-Path $env:WINDIR 'Logs\CBS'; Pattern = '*'; Recurse = $true }
    )

    if ($Config.Safe.Thumbnails) {
        $targets += @{ Name = 'Thumbnail Cache'; Path = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'; Pattern = 'thumbcache_*.db'; Recurse = $false }
    }

    return $targets
}

function Invoke-UscTempCleanup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][psobject]$Config,
        [switch]$WhatIfOnly
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $targets = Get-UscTempTargets -Config $Config

    foreach ($target in $targets) {
        # Check if target path has wildcard characters (e.g. Installer\$MSI*) and resolve
        $pathsToClean = @()
        if ($target.Path -like '*[*?]*') {
            $pathsToClean = @(Get-Item -Path $target.Path -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        }
        else {
            if (Test-Path -LiteralPath $target.Path) {
                $pathsToClean = @($target.Path)
            }
        }

        if ($pathsToClean.Count -eq 0) {
            $results.Add((New-UscOperationResult -Name $target.Name -Category Clean -Status Skipped -Message 'Path does not exist' -Paths @($target.Path)))
            continue
        }

        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($cleanPath in $pathsToClean) {
            $rawItems = Get-ChildItem -LiteralPath $cleanPath -Filter $target.Pattern -Force -ErrorAction SilentlyContinue -Recurse:([bool]$target.Recurse)
            foreach ($item in $rawItems) {
                # Ensure it's not excluded and not a reparse point
                if (-not (Test-UscExcludedPath -Path $item.FullName -Exclusions $Config.Exclusions) -and 
                    -not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                    $items.Add($item)
                }
            }
        }

        $before = Measure-UscObjectSum -InputObject $items.ToArray() -Property Length
        $freed = 0
        $failed = 0
        $maxRetries = 3

        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                # Skip folders in the initial file deletion pass to prevent errors. We will clean empty folders later.
                continue
            }

            $size = if ($null -eq $item.Length) { 0 } else { [Int64]$item.Length }
            
            if ($WhatIfOnly) {
                $freed += $size
                continue
            }

            if ($PSCmdlet.ShouldProcess($item.FullName, "Remove file ($target.Name)")) {
                $success = $false
                for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
                    try {
                        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                        $freed += $size
                        $success = $true
                        break
                    }
                    catch {
                        if ($attempt -lt $maxRetries) {
                            Start-Sleep -Milliseconds 50
                        }
                    }
                }
                if (-not $success) {
                    $failed++
                    Write-UscLog -Level Debug -Message "Unable to remove locked temp file after $maxRetries attempts: $($item.FullName)"
                }
            }
        }

        # Try to clean up empty subfolders if recursive targets
        if ($target.Recurse -and -not $WhatIfOnly) {
            foreach ($cleanPath in $pathsToClean) {
                $folders = Get-ChildItem -LiteralPath $cleanPath -Directory -Force -Recurse -ErrorAction SilentlyContinue |
                    Sort-Object { $_.FullName.Length } -Descending
                foreach ($folder in $folders) {
                    try {
                        $subContents = @(Get-ChildItem -LiteralPath $folder.FullName -Force -ErrorAction SilentlyContinue)
                        if ($subContents.Count -eq 0) {
                            Remove-Item -LiteralPath $folder.FullName -Force -ErrorAction Stop
                        }
                    }
                    catch {
                        # Suppress errors for directories that can't be deleted because they aren't empty or are locked
                    }
                }
            }
        }

        $status = if ($WhatIfOnly) {
            if ($failed -gt 0) { 'PartiallySucceeded' } else { 'Simulated' }
        } elseif ($failed -gt 0 -and $freed -gt 0) { 'PartiallySucceeded' } elseif ($failed -gt 0) { 'Failed' } else { 'Succeeded' }
        $msg = if ($WhatIfOnly) { "$($items.Count) items would be removed" } else { "$($items.Count) candidate items, $failed failures" }
        $results.Add((New-UscOperationResult -Name $target.Name -Category Clean -Status $status -BytesBefore $before -BytesFreed $freed -Paths $pathsToClean -Message $msg))
    }
    return @($results)
}

Export-ModuleMember -Function Get-UscTempTargets, Invoke-UscTempCleanup

