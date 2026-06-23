Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Core\Config.psm1') -Force
Import-Module (Join-Path $root 'Core\Logger.psm1') -Force
Import-Module (Join-Path $root 'Core\Signature.psm1') -Force
Import-Module (Join-Path $root 'Core\RunspaceManager.psm1') -Force
Import-Module (Join-Path $root 'Analysis\DiskAnalyzer.psm1') -Force

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
}

Describe 'UltimateSystemCleaner result objects' {
    It 'creates operation results' {
        $result = New-UscOperationResult -Name 'Example' -Category Analyze -Status Succeeded -BytesFreed 42
        $result.Name | Should Be 'Example'
        $result.BytesFreed | Should Be 42
    }
}

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
        # Initialize multiple logs
        for ($i = 1; $i -le 12; $i++) {
            $null = Initialize-UscLogger -LogDirectory $script:LogTestDir -RunId "run-$i" -MaxLogFiles 5
            Start-Sleep -Milliseconds 10
        }
        $logFiles = Get-ChildItem -LiteralPath $script:LogTestDir -Filter 'UltimateSystemCleaner-*.log' -File
        # Should be restricted to exactly 5 log files max
        $logFiles.Count | Should Be 5
    }
}

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

Describe 'UltimateSystemCleaner Directory Sizing & Reparse Point Filtering' {
    BeforeAll {
        $script:SizeTestDir = Join-Path $PSScriptRoot 'SizeTest'
        if (-not (Test-Path -LiteralPath $script:SizeTestDir)) {
            New-Item -ItemType Directory -Path $script:SizeTestDir -Force | Out-Null
        }
        # Create mock file structure
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
        $subFolder.Bytes | Should Be 5  # Length of 'Hello'
        
        $rootFile = $dirSizes | Where-Object { $_.Name -eq 'file2.txt' }
        $rootFile.Bytes | Should Be 8  # Length of 'World123'
    }
}

