Set-StrictMode -Version Latest

function Invoke-UscWindowsUpdateCleanup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][psobject]$Config,
        [switch]$WhatIfOnly
    )

    $path = Join-Path $env:WINDIR 'SoftwareDistribution\Download'
    if (-not (Test-Path -LiteralPath $path)) {
        return New-UscOperationResult -Name 'Windows Update Cache' -Category Clean -Status Skipped -Paths @($path) -Message 'Path does not exist'
    }

    $items = @(Get-ChildItem -LiteralPath $path -Force -Recurse -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer -and -not (Test-UscExcludedPath -Path $_.FullName -Exclusions $Config.Exclusions) })
    $size = Measure-UscObjectSum -InputObject $items -Property Length

    if ($WhatIfOnly) {
        return New-UscOperationResult -Name 'Windows Update Cache' -Category Clean -Status Simulated -BytesFreed $size -Paths @($path) -Message 'Dry run: update download cache would be purged'
    }

    $services = @('wuauserv', 'bits', 'dosvc', 'CryptSvc')
    $stoppedServices = [System.Collections.Generic.List[string]]::new()

    foreach ($service in $services) {
        try {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') {
                Write-UscLog -Level Information -Message "Stopping service '$service' for update cache cleanup..."
                Stop-Service -Name $service -Force -ErrorAction Stop
                $stoppedServices.Add($service)
            }
        }
        catch {
            Write-UscLog -Level Warning -Message "Could not stop service '$service'" -Exception $_.Exception
        }
    }

    $failed = 0
    $freed = 0
    try {
        foreach ($item in $items) {
            try {
                if ($PSCmdlet.ShouldProcess($item.FullName, 'Remove Windows Update cache item')) {
                    $itemSize = $item.Length
                    Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                    $freed += $itemSize
                }
            }
            catch {
                $failed++
                Write-UscLog -Level Debug -Message "Failed to remove update cache item: $($item.FullName)"
            }
        }

        # Attempt to remove empty directories
        $subfolders = Get-ChildItem -LiteralPath $path -Directory -Force -Recurse -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending
        foreach ($dir in $subfolders) {
            try {
                $contents = @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue)
                if ($contents.Count -eq 0) {
                    Remove-Item -LiteralPath $dir.FullName -Force -ErrorAction Stop
                }
            }
            catch {}
        }
    }
    finally {
        # Restart all services that were running before we stopped them
        foreach ($service in $stoppedServices) {
            try {
                Write-UscLog -Level Information -Message "Restarting service '$service'..."
                Start-Service -Name $service -ErrorAction Stop
            }
            catch {
                Write-UscLog -Level Warning -Message "Could not restart service '$service'" -Exception $_.Exception
            }
        }
    }

    $status = if ($failed -gt 0 -and $freed -gt 0) { 'PartiallySucceeded' } elseif ($failed -gt 0) { 'Failed' } else { 'Succeeded' }
    return New-UscOperationResult -Name 'Windows Update Cache' -Category Clean -Status $status -BytesFreed $freed -Paths @($path) -Message "$($items.Count) candidate items, $failed failures"
}

function Invoke-UscStorageSense {
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$WhatIfOnly)

    if ($WhatIfOnly) {
        return New-UscOperationResult -Name 'Storage Sense' -Category Configure -Status Skipped -Message 'Dry run: Storage Sense scheduled run would be requested'
    }

    try {
        if ($PSCmdlet.ShouldProcess('Storage Sense', 'Start built-in cleanup task')) {
            # cleanmgr /verylowdisk runs cleanmgr silently on all drives
            Start-Process -FilePath "$env:WINDIR\System32\cleanmgr.exe" -ArgumentList '/verylowdisk' -WindowStyle Hidden
            return New-UscOperationResult -Name 'Storage Sense' -Category Configure -Status Succeeded -Message 'Requested built-in cleanup pass'
        }
    }
    catch {
        Write-UscLog -Level Warning -Message 'Storage Sense integration failed' -Exception $_.Exception
        return New-UscOperationResult -Name 'Storage Sense' -Category Configure -Status Failed -Message $_.Exception.Message
    }
}

Export-ModuleMember -Function Invoke-UscWindowsUpdateCleanup, Invoke-UscStorageSense

