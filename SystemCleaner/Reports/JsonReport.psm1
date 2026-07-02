Set-StrictMode -Version Latest

function New-UscJsonReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Run,
        [Parameter(Mandatory)][string]$OutputDirectory
    )

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $fileName = "UltimateSystemCleaner-$($Run.RunId).json"
    $outputPath = Join-Path $OutputDirectory $fileName

    $payload = [ordered]@{
        RunId           = $Run.RunId
        Mode            = $Run.Mode
        Started         = $Run.Started
        Finished        = $Run.Finished
        ComputerName    = $Run.ComputerName
        UserName        = $Run.UserName
        IsAdministrator = $Run.IsAdministrator
        WhatIfOnly      = $Run.WhatIfOnly
        TotalBytesFreed = $Run.TotalBytesFreed
        Before          = @($Run.Before)
        After           = @($Run.After)
        Results         = @($Run.Results)
    }

    $payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputPath -Encoding UTF8
    return $outputPath
}

Export-ModuleMember -Function New-UscJsonReport
