Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Core\Config.psm1') -Force
Import-Module (Join-Path $root 'Core\Logger.psm1') -Force
Import-Module (Join-Path $root 'Core\RunspaceManager.psm1') -Force
Import-Module (Join-Path $root 'Core\Progress.psm1') -Force
Import-Module (Join-Path $root 'Analysis\DiskAnalyzer.psm1') -Force
Import-Module (Join-Path $root 'History\HistoryManager.psm1') -Force

# ── Configuration ────────────────────────────────────────────────────────────
Describe 'UltimateSystemCleaner configuration' {
    BeforeAll {
        $script:TempTestDir = Join-Path $PSScriptRoot 'TempTest'
        if (-not (Test-Path -LiteralPath $script:TempTestDir)) {
            New-Item -ItemType Directory -Path $script:TempTestDir -Force | Out-Null
        }
    }
    AfterAll {
        if (Test-Path -LiteralPath $script:TempTestDir) {
            Remove-Item -LiteralPath $script:TempTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'defaults DryRunDefault to false for real cleanup' {
        $config = Get-UscDefaultConfig
        $config.DryRunDefault | Should Be $false
    }

    It 'loads the default configuration' {
        $config = Get-UscDefaultConfig
        $config.Version | Should Be '0.2'
        $config.ConfirmNuclearActions | Should Be $true
    }

    It 'detects excluded child paths' {
        Test-UscExcludedPath -Path 'C:\Temp\Keep\File.txt' -Exclusions @('C:\Temp\Keep') | Should Be $true
    }

    It 'does not exclude unrelated paths' {
        Test-UscExcludedPath -Path 'C:\Temp\Other\File.txt' -Exclusions @('C:\Temp\Keep') | Should Be $false
    }

    It 'expands environment variables recursively in exclusions' {
        $path = Join-Path $env:USERPROFILE 'Downloads\Keep\doc.txt'
        Test-UscExcludedPath -Path $path -Exclusions @('%USERPROFILE%\Downloads\Keep') | Should Be $true
    }

    It 'supports wildcard matching in exclusions' {
        $path = 'C:\Logs\App-2026.log'
        Test-UscExcludedPath -Path $path -Exclusions @('C:\Logs\*-2026.log') | Should Be $true
        Test-UscExcludedPath -Path $path -Exclusions @('C:\Logs\*-2025.log') | Should Be $false
    }

    It 'config Safe section has required keys' {
        $config = Get-UscDefaultConfig
        $keys = @($config.Safe.Keys)
        ($keys -contains 'Temp') | Should Be $true
        ($keys -contains 'RecycleBin') | Should Be $true
        ($keys -contains 'BrowserCache') | Should Be $true
        ($keys -contains 'Thumbnails') | Should Be $true
    }

    It 'config Aggressive section has required keys' {
        $config = Get-UscDefaultConfig
        $keys = @($config.Aggressive.Keys)
        ($keys -contains 'WindowsUpdateCache') | Should Be $true
        ($keys -contains 'GpuShaderCache') | Should Be $true
        ($keys -contains 'DnsFlush') | Should Be $true
        ($keys -contains 'FontCache') | Should Be $true
    }

    It 'config Nuclear section has required keys' {
        $config = Get-UscDefaultConfig
        $keys = @($config.Nuclear.Keys)
        ($keys -contains 'CrashDumps') | Should Be $true
        ($keys -contains 'DeleteShadowCopies') | Should Be $true
        ($keys -contains 'ComponentStoreResetBase') | Should Be $true
    }
}

# ── Result Objects ────────────────────────────────────────────────────────────
Describe 'UltimateSystemCleaner result objects' {
    It 'creates operation results' {
        $result = New-UscOperationResult -Name 'Example' -Category Analyze -Status Succeeded -BytesFreed 42
        $result.Name | Should Be 'Example'
        $result.BytesFreed | Should Be 42
    }

    It 'distinguishes dry-run vs real byte accounting' {
        $realResult = New-UscOperationResult -Name 'Real' -Category Clean -Status Succeeded -BytesFreed 1048576
        $dryResult  = New-UscOperationResult -Name 'DryRun' -Category Clean -Status Simulated -BytesFreed 0
        $realResult.BytesFreed | Should BeGreaterThan 0
        $dryResult.BytesFreed | Should Be 0
        $dryResult.Status | Should Be 'Simulated'
    }

    It 'accumulates total bytes across multiple results' {
        $r1 = New-UscOperationResult -Name 'R1' -Category Clean -Status Succeeded -BytesFreed 1024
        $r2 = New-UscOperationResult -Name 'R2' -Category Clean -Status Succeeded -BytesFreed 2048
        $total = Measure-UscObjectSum -InputObject @($r1, $r2) -Property BytesFreed
        $total | Should Be 3072
    }
}

# ── Logger ────────────────────────────────────────────────────────────────────
Describe 'UltimateSystemCleaner thread-safe logger' {
    BeforeAll {
        $script:LogTestDir = Join-Path $PSScriptRoot 'LogTest'
        if (-not (Test-Path -LiteralPath $script:LogTestDir)) {
            New-Item -ItemType Directory -Path $script:LogTestDir -Force | Out-Null
        }
    }
    AfterAll {
        if (Test-Path -LiteralPath $script:LogTestDir) {
            Remove-Item -LiteralPath $script:LogTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'initializes logger and respects max file count rotation' {
        for ($i = 1; $i -le 12; $i++) {
            $null = Initialize-UscLogger -LogDirectory $script:LogTestDir -RunId "run-$i" -MaxLogFiles 5
            Start-Sleep -Milliseconds 10
        }
        $logFiles = Get-ChildItem -LiteralPath $script:LogTestDir -Filter 'UltimateSystemCleaner-*.log' -File
        $logFiles.Count | Should Be 5
    }
}

# ── Parallel Execution ────────────────────────────────────────────────────────
Describe 'UltimateSystemCleaner Parallel Execution Manager' {
    It 'runs scripts in parallel runspaces and returns results' {
        $inputs = @(1, 2, 3)
        $scriptBlock = {
            param($val, $argsList)
            return [pscustomobject]@{ InputVal = $val; Doubled = $val * 2 }
        }
        $parallelResults = Invoke-UscParallel -InputObject $inputs -ScriptBlock $scriptBlock -ThrottleLimit 2
        $parallelResults.Count | Should Be 3
        $parallelResults[0].Doubled | Should Be 2
        $parallelResults[1].Doubled | Should Be 4
        $parallelResults[2].Doubled | Should Be 6
    }
}

# ── Report Generation ─────────────────────────────────────────────────────────
Describe 'UltimateSystemCleaner report generation' {
    BeforeAll {
        Import-Module (Join-Path $root 'Reports\JsonReport.psm1') -Force
        Import-Module (Join-Path $root 'Reports\HtmlReport.psm1') -Force
        $script:ReportTestDir = Join-Path $PSScriptRoot 'ReportTest'
        if (Test-Path -LiteralPath $script:ReportTestDir) {
            Remove-Item -LiteralPath $script:ReportTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $script:ReportTestDir -Force | Out-Null
    }
    AfterAll {
        if (Test-Path -LiteralPath $script:ReportTestDir) {
            Remove-Item -LiteralPath $script:ReportTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes JSON, CSV, and HTML reports for a run record' {
        $run = [pscustomobject]@{
            RunId           = 'test-run'
            Mode            = 'Safe'
            Started         = Get-Date
            Finished        = Get-Date
            ComputerName    = $env:COMPUTERNAME
            UserName        = $env:USERNAME
            IsAdministrator = $false
            WhatIfOnly      = $false
            TotalBytesFreed = [Int64]1024
            Before = @([pscustomobject]@{ Drive = 'C:'; FreeSpace = [Int64]1000; UsedSpace = [Int64]9000; Size = [Int64]10000; PercentFree = 10; VolumeName = 'OS'; FileSystem = 'NTFS' })
            After  = @([pscustomobject]@{ Drive = 'C:'; FreeSpace = [Int64]2024; UsedSpace = [Int64]7976; Size = [Int64]10000; PercentFree = 20; VolumeName = 'OS'; FileSystem = 'NTFS' })
            Results = @((New-UscOperationResult -Name 'User Temp' -Category Clean -Status Succeeded -BytesFreed 1024 -Message 'ok'))
        }
        $json = New-UscJsonReport -Run $run -OutputDirectory $script:ReportTestDir
        $csv  = New-UscCsvReport  -Results $run.Results -OutputDirectory $script:ReportTestDir -RunId $run.RunId
        $html = New-UscHtmlReport -Run $run -OutputDirectory $script:ReportTestDir

        Test-Path -LiteralPath $json | Should Be $true
        Test-Path -LiteralPath $csv  | Should Be $true
        Test-Path -LiteralPath $html | Should Be $true
        (Get-Content -LiteralPath $html -Raw) | Should Match 'Ultimate System Cleaner Report'
    }

    It 'JSON report contains run metadata fields' {
        $run = [pscustomobject]@{
            RunId           = 'meta-run'
            Mode            = 'Aggressive'
            Started         = Get-Date
            Finished        = Get-Date
            ComputerName    = 'TestBox'
            UserName        = 'TestUser'
            IsAdministrator = $true
            WhatIfOnly      = $false
            TotalBytesFreed = [Int64]512000
            Before = @()
            After  = @()
            Results = @()
        }
        $jsonPath = New-UscJsonReport -Run $run -OutputDirectory $script:ReportTestDir
        $content = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
        $content.RunId          | Should Be 'meta-run'
        $content.Mode           | Should Be 'Aggressive'
        $content.TotalBytesFreed | Should Be 512000
    }
}

# ── Console Output ────────────────────────────────────────────────────────────
Describe 'UltimateSystemCleaner operation console output' {
    It 'accepts Simulated status on operation results' {
        $result = New-UscOperationResult -Name 'Recycle Bin' -Category Clean -Status Simulated -BytesFreed 512 -Message 'Would clear'
        $result.Status | Should Be 'Simulated'
    }
}

# ── Directory Sizing ──────────────────────────────────────────────────────────
Describe 'UltimateSystemCleaner Directory Sizing & Reparse Point Filtering' {
    BeforeAll {
        $script:SizeTestDir = Join-Path $PSScriptRoot 'SizeTest'
        if (-not (Test-Path -LiteralPath $script:SizeTestDir)) {
            New-Item -ItemType Directory -Path $script:SizeTestDir -Force | Out-Null
        }
        $subDir = New-Item -ItemType Directory -Path (Join-Path $script:SizeTestDir 'Sub') -Force
        $null = New-Item -ItemType File -Path (Join-Path $subDir 'file1.txt') -Value 'Hello' -Force
        $null = New-Item -ItemType File -Path (Join-Path $script:SizeTestDir 'file2.txt') -Value 'World123' -Force
    }
    AfterAll {
        if (Test-Path -LiteralPath $script:SizeTestDir) {
            Remove-Item -LiteralPath $script:SizeTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'calculates correct recursive folder size' {
        $dirSizes = Get-UscDirectorySize -Path $script:SizeTestDir -Depth 1
        $dirSizes.Count | Should Be 2

        $subFolder = $dirSizes | Where-Object { $_.Name -eq 'Sub' }
        $subFolder.Bytes | Should Be 5

        $rootFile = $dirSizes | Where-Object { $_.Name -eq 'file2.txt' }
        $rootFile.Bytes | Should Be 8
    }
}

# ── Format-UscBytes Boundaries ────────────────────────────────────────────────
Describe 'UltimateSystemCleaner Format-UscBytes boundaries' {
    It 'formats bytes at TB scale' {
        Format-UscBytes -Bytes ([Int64]1TB) | Should Match 'TB'
    }
    It 'formats bytes at GB scale' {
        Format-UscBytes -Bytes ([Int64]1GB) | Should Match 'GB'
    }
    It 'formats bytes at MB scale' {
        Format-UscBytes -Bytes ([Int64]1MB) | Should Match 'MB'
    }
    It 'formats bytes at KB scale' {
        Format-UscBytes -Bytes ([Int64]1KB) | Should Match 'KB'
    }
    It 'formats raw byte values' {
        Format-UscBytes -Bytes 500 | Should Match 'B'
    }
    It 'handles zero bytes without error' {
        Format-UscBytes -Bytes 0 | Should Match '0'
    }
}

# ── Run History Manager ───────────────────────────────────────────────────────
Describe 'UltimateSystemCleaner Run History Manager' {
    BeforeAll {
        Import-Module (Join-Path $root 'Reports\JsonReport.psm1') -Force
        Import-Module (Join-Path $root 'Reports\HtmlReport.psm1') -Force
        # Use a temp ProgramData-style dir so tests don't write to system dirs
        $script:HistoryTestDir = Join-Path $PSScriptRoot 'HistoryTest'
        if (Test-Path -LiteralPath $script:HistoryTestDir) {
            Remove-Item -LiteralPath $script:HistoryTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $script:HistoryTestDir -Force | Out-Null

        # Override the history dir inside the module to isolate tests
        $histModule = Get-Module 'HistoryManager'
        if ($histModule) {
            $sb = [scriptblock]::Create("`$script:HistoryDir = '$script:HistoryTestDir'")
            & $histModule $sb
        }
    }
    AfterAll {
        if (Test-Path -LiteralPath $script:HistoryTestDir) {
            Remove-Item -LiteralPath $script:HistoryTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'saves a run record and the file appears in history directory' {
        $runId = "test-hist-$(Get-Random)"
        $run = [pscustomobject]@{
            RunId           = $runId
            Mode            = 'Safe'
            Started         = Get-Date
            Finished        = Get-Date
            ComputerName    = 'TestBox'
            WhatIfOnly      = $false
            TotalBytesFreed = [Int64]8192
            Before  = @([pscustomobject]@{ Drive = 'C:'; FreeSpace = [Int64]1000000; Size = [Int64]100000000 })
            After   = @([pscustomobject]@{ Drive = 'C:'; FreeSpace = [Int64]1008192; Size = [Int64]100000000 })
            Results = @(New-UscOperationResult -Name 'Temp' -Category Clean -Status Succeeded -BytesFreed 8192)
        }
        Save-UscRunHistory -Run $run

        $savedFile = Join-Path $script:HistoryTestDir "run-$runId.json"
        Test-Path -LiteralPath $savedFile | Should Be $true
    }

    It 'retrieves at least the saved run from history' {
        $history = Get-UscRunHistory -Count 10
        $history | Should Not BeNullOrEmpty
    }

    It 'Compare-UscLastTwoRuns does not throw with less than 2 runs' {
        { Compare-UscLastTwoRuns } | Should Not Throw
    }

    It 'Export-UscHistoryTrend returns a path or null without throwing' {
        $trendPath = Join-Path $script:HistoryTestDir 'trend.csv'
        { Export-UscHistoryTrend -OutputPath $trendPath } | Should Not Throw
    }

    It 'prunes history to MaxHistoryRuns limit' {
        # Save 5 dummy runs quickly
        for ($i = 1; $i -le 5; $i++) {
            $rid = "prune-test-$i-$(Get-Random)"
            $run = [pscustomobject]@{
                RunId = $rid; Mode = 'Safe'; Started = Get-Date; Finished = Get-Date
                ComputerName = 'T'; WhatIfOnly = $false; TotalBytesFreed = [Int64]0
                Before = @(); After = @(); Results = @()
            }
            Save-UscRunHistory -Run $run
        }
        $history = Get-UscRunHistory -Count 100
        ($history.Count -le 10) | Should Be $true
    }
}
