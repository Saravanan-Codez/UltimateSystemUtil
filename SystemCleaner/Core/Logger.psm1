Set-StrictMode -Version Latest

$script:LogRoot = Join-Path $env:ProgramData 'UltimateSystemCleaner\Logs'
$script:CurrentLogFile = $null
$script:AuditTrail = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:LogMutexName = 'Global\UltimateSystemCleaner-LogMutex'

function Initialize-UscLogger {
    [CmdletBinding()]
    param(
        [string]$LogDirectory = $script:LogRoot,
        [string]$RunId = (Get-Date -Format 'yyyyMMdd-HHmmss'),
        [int]$MaxLogFiles = 10
    )

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $script:LogRoot = $LogDirectory
    $script:CurrentLogFile = Join-Path $LogDirectory "UltimateSystemCleaner-$RunId.log"
    
    # Clear existing thread-safe queue by instantiating a new one
    $script:AuditTrail = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    
    # Perform log rotation
    try {
        $logFiles = @(Get-ChildItem -LiteralPath $LogDirectory -Filter 'UltimateSystemCleaner-*.log' -File | 
            Sort-Object LastWriteTime -Descending)
        if ($logFiles.Count -ge $MaxLogFiles) {
            $filesToDelete = $logFiles | Select-Object -Skip ($MaxLogFiles - 1)
            foreach ($file in $filesToDelete) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        # Non-fatal error during rotation should not block initialization
    }

    Write-UscLog -Level Information -Message 'Logger initialized' -Data @{ RunId = $RunId; LogFile = $script:CurrentLogFile; MaxLogs = $MaxLogFiles }
    return $script:CurrentLogFile
}

function Write-UscLog {
    [CmdletBinding()]
    param(
        [ValidateSet('Debug','Information','Warning','Error','Critical','Audit')]
        [string]$Level = 'Information',
        [Parameter(Mandatory)]
        [string]$Message,
        [hashtable]$Data = @{},
        [System.Exception]$Exception
    )

    $entry = [ordered]@{
        Timestamp = (Get-Date).ToString('o')
        Level     = $Level
        Message   = $Message
        Data      = $Data
        Error     = if ($Exception) { $Exception.Message } else { $null }
    }

    $script:AuditTrail.Enqueue([pscustomobject]$entry)
    
    # Machine readable JSON format for the log file
    $line = $entry | ConvertTo-Json -Depth 8 -Compress

    if (-not $script:CurrentLogFile) {
        $null = Initialize-UscLogger
    }

    # Thread-safe write using System.Threading.Mutex
    $createdNew = $false
    $mutex = [System.Threading.Mutex]::new($false, $script:LogMutexName, [ref]$createdNew)
    try {
        $acquired = $mutex.WaitOne(5000) # Wait up to 5 seconds
        if ($acquired) {
            Add-Content -LiteralPath $script:CurrentLogFile -Value $line -Encoding UTF8
        }
        else {
            Write-Warning "Could not acquire log mutex within 5 seconds for message: $Message"
        }
    }
    catch {
        # Fallback to direct write if mutex fails
        Add-Content -LiteralPath $script:CurrentLogFile -Value $line -Encoding UTF8
    }
    finally {
        if ($acquired) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }

    # Output to console streams
    switch ($Level) {
        'Warning' { Write-Warning $Message }
        'Error' { Write-Error $Message -ErrorAction Continue }
        'Critical' { Write-Error $Message -ErrorAction Continue }
        default { Write-Verbose $Message }
    }
}

function Get-UscAuditTrail {
    [CmdletBinding()]
    param()

    return $script:AuditTrail.ToArray()
}

function New-UscOperationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Analyze','Clean','Configure','Report','Checkpoint')][string]$Category,
        [ValidateSet('Pending','Skipped','Succeeded','Failed','PartiallySucceeded','Simulated')]
        [string]$Status = 'Pending',
        [Int64]$BytesBefore = 0,
        [Int64]$BytesAfter = 0,
        [Int64]$BytesFreed = 0,
        [string[]]$Paths = @(),
        [string]$Message = '',
        [hashtable]$Metadata = @{}
    )

    [pscustomobject]@{
        PSTypeName  = 'UltimateSystemCleaner.OperationResult'
        Name        = $Name
        Category    = $Category
        Status      = $Status
        BytesBefore = $BytesBefore
        BytesAfter  = $BytesAfter
        BytesFreed  = $BytesFreed
        Paths       = $Paths
        Message     = $Message
        Metadata    = $Metadata
        Timestamp   = Get-Date
    }
}

function Measure-UscObjectSum {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$InputObject = @(),
        [string]$Property = 'Length'
    )

    $total = 0
    foreach ($item in @($InputObject)) {
        if ($null -eq $item) { continue }
        $value = $null
        if ($item.PSObject.Properties.Name -contains $Property) {
            $value = $item.$Property
        }
        if ($null -ne $value) {
            $total += [Int64]$value
        }
    }
    return $total
}

function Write-UscOperationConsole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Result,
        [switch]$WhatIfOnly
    )

    # Clear active console progress line to prevent overlapping characters
    if ([Environment]::UserInteractive) {
        Write-Host ("`r" + (' ' * 110) + "`r") -NoNewline
    }

    $icon = switch ($Result.Status) {
        'Succeeded' { '[OK]' }
        'PartiallySucceeded' { '[!!]' }
        'Simulated' { '[~]' }
        'Failed' { '[X]' }
        'Skipped' { '[--]' }
        default { '[..]' }
    }

    $sizePart = if ($Result.BytesFreed -gt 0) {
        $b = [Int64]$Result.BytesFreed
        if ($b -ge 1GB) { " {0:N2} GB" -f ($b / 1GB) }
        elseif ($b -ge 1MB) { " {0:N2} MB" -f ($b / 1MB) }
        elseif ($b -ge 1KB) { " {0:N2} KB" -f ($b / 1KB) }
        else { " $b B" }
    } else { '' }

    $color = switch ($Result.Status) {
        'Succeeded' { 'Green' }
        'PartiallySucceeded' { 'Yellow' }
        'Simulated' { 'Magenta' }
        'Failed' { 'Red' }
        'Skipped' { 'DarkGray' }
        default { 'Gray' }
    }

    $suffix = if ($Result.Message) { " - $($Result.Message)" } else { '' }
    Write-Host "  $icon $($Result.Name)$sizePart$suffix" -ForegroundColor $color
}

Export-ModuleMember -Function Initialize-UscLogger, Write-UscLog, Get-UscAuditTrail, New-UscOperationResult, Measure-UscObjectSum, Write-UscOperationConsole

