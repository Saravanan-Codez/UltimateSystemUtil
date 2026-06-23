Set-StrictMode -Version Latest

function Get-UscDefaultConfig {
    [CmdletBinding()]
    param()
    $config = [pscustomobject]@{
        LogDirectory = Join-Path $env:ProgramData 'UltimateSystemCleaner\Logs'
        ReportDirectory = Join-Path $env:ProgramData 'UltimateSystemCleaner\Reports'
        MaxRunspaces = [Math]::Max(2, [Environment]::ProcessorCount)
        ConfirmNuclearActions = $true
        CreateRestorePoint = $true
        EnableStorageSenseIntegration = $true
        DryRunDefault = $true
        Exclusions = @(
            '%USERPROFILE%\Downloads\Keep',
            '%ProgramData%\Package Cache'
        )
        Safe = @{
            Temp = $true
            RecycleBin = $true
            Thumbnails = $true
            BrowserCache = $false
        }
        Aggressive = @{
            WindowsErrorReporting = $true
            WindowsUpdateCache = $true
            GpuShaderCache = $true
            BrowserCache = $true
        }
        Nuclear = @{
            CrashDumps = $true
            ComponentStoreResetBase = $false
            DeleteShadowCopies = $false
            RemoveRestorePoints = $false
            PurgeUpdateRollback = $false
        }
    }
    $config | Add-Member -MemberType NoteProperty -Name 'Version' -Value '0.2' -Force
    return $config
}

function Read-UscConfig {
    [CmdletBinding()]
    param(
        [string]$Path = (Join-Path $PSScriptRoot '..\Config\settings.json')
    )

    $default = Get-UscDefaultConfig
    if (-not (Test-Path -LiteralPath $Path)) {
        return $default
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $loaded = $raw | ConvertFrom-Json -ErrorAction Stop
        $merged = Merge-UscConfig -Base $default -Override $loaded
        return $merged
    }
    catch {
        Write-Error "Failed to read configuration '$Path': $($_.Exception.Message)"
        return $default
    }
}

function Merge-UscConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Base,
        [Parameter(Mandatory)][psobject]$Override
    )

    # Deep clone base config by converting to/from JSON
    $merged = $Base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    
    foreach ($property in $Override.PSObject.Properties) {
        if ($null -eq $property.Value) { continue }
        
        # If the property exists in Base and is a nested object
        if ($merged.PSObject.Properties.Name -contains $property.Name) {
            $baseValue = $merged.$($property.Name)
            if ($property.Value -is [pscustomobject] -and $baseValue -is [pscustomobject]) {
                # Recursively merge child properties
                foreach ($child in $property.Value.PSObject.Properties) {
                    $merged.$($property.Name).$($child.Name) = $child.Value
                }
            }
            elseif ($property.Value -is [System.Array] -or $property.Value -is [System.Collections.IList]) {
                # For arrays (like Exclusions), combine or overwrite. Let's overwrite exclusions but verify values are clean.
                $merged.$($property.Name) = @($property.Value)
            }
            else {
                $merged.$($property.Name) = $property.Value
            }
        }
        else {
            # Add dynamic property if not in base config
            $merged | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value -Force
        }
    }
    return $merged
}

function Test-UscExcludedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Exclusions = @()
    )

    if (-not $Path) { return $false }
    $fullPath = try { [IO.Path]::GetFullPath($Path) } catch { $Path }
    
    foreach ($exclusion in $Exclusions) {
        if ([string]::IsNullOrWhiteSpace($exclusion)) { continue }
        
        # Recursively expand environment variables in the exclusion string
        $expanded = $exclusion
        while ($expanded -match '%([^%]+)%') {
            $varName = $matches[1]
            $envVal = [Environment]::GetEnvironmentVariable($varName)
            if ($null -eq $envVal) { $envVal = '' }
            $expanded = $expanded -replace "%$varName%", $envVal
        }
        
        $fullExclusion = try { [IO.Path]::GetFullPath($expanded) } catch { $expanded }

        # Wildcard pattern comparison if it contains * or ?
        if ($fullExclusion -match '\*|\?') {
            if ($fullPath -like $fullExclusion) {
                return $true
            }
        }
        else {
            # Precise folder/file check
            $cleanExclusion = $fullExclusion.TrimEnd([System.IO.Path]::DirectorySeparatorChar)
            $cleanPath = $fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar)

            # Match if exact same path, or if current path lies inside the excluded folder path
            if ($cleanPath -eq $cleanExclusion -or 
                $fullPath.StartsWith($cleanExclusion + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }
    return $false
}

function Save-UscConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][psobject]$Config,
        [string]$Path = (Join-Path $PSScriptRoot '..\Config\settings.json')
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Write cleaner configuration')) {
        $json = $Config | ConvertTo-Json -Depth 20
        $json | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}

Export-ModuleMember -Function Get-UscDefaultConfig, Read-UscConfig, Save-UscConfig, Test-UscExcludedPath, Merge-UscConfig

