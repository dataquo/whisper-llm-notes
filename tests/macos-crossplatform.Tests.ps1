Describe "macOS and Cross-Platform Compatibility Tests (v07.00)" {
    BeforeAll {
        $EngineScriptPath = Join-Path $PSScriptRoot "..\src\whisper-asr-service-docker.ps1"
        $MasterScriptPath = Join-Path $PSScriptRoot "..\src\_MASTER_WHISPER.ps1"

        $EngineContent = Get-Content -LiteralPath $EngineScriptPath -Raw -Encoding UTF8
        $MasterContent = Get-Content -LiteralPath $MasterScriptPath -Raw -Encoding UTF8

        # Extract functions and inject into global scope
        if ($EngineContent -match '(?ms)function Test-IsWindowsPlatform\s*\{(.+?^\})') {
            $fnBody = "function global:Test-IsWindowsPlatform { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        if ($EngineContent -match '(?ms)function Get-PlatformBinaryName\s*\{(.+?^\})') {
            $fnBody = "function global:Get-PlatformBinaryName { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        if ($EngineContent -match '(?ms)function Get-PipelineConfig\s*\{(.+?^\})') {
            $fnBody = "function global:Get-PipelineConfig { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        if ($EngineContent -match '(?ms)function Test-WhisperServiceHealth\s*\{(.+?^\})') {
            $fnBody = "function global:Test-WhisperServiceHealth { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        if ($EngineContent -match '(?ms)function Get-SystemInfo\s*\{(.+?^\})') {
            $fnBody = "function global:Get-SystemInfo { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        if ($EngineContent -match '(?ms)function Get-WhisperContainerMetadata\s*\{(.+?^\})') {
            $fnBody = "function global:Get-WhisperContainerMetadata { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        if ($EngineContent -match '(?ms)function Ensure-WhisperContainerRunning\s*\{(.+?^\})') {
            $fnBody = "function global:Ensure-WhisperContainerRunning { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        if ($EngineContent -match '(?ms)function Restart-WhisperContainer\s*\{(.+?^\})') {
            $fnBody = "function global:Restart-WhisperContainer { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }

        if ($MasterContent -match '(?ms)function Get-MissingMdFiles\s*\{(.+?^\})') {
            $fnBody = "function global:Get-MissingMdFiles { $($Matches[1])"
            . ([ScriptBlock]::Create($fnBody))
        }
    }

    Context "Canonical Script Version (v07.00)" {
        It "Matches canonical script version v07.00 in engine" {
            $match = $EngineContent -match '\$ScriptVersionNumber\s*=\s*"v07\.00"'
            $match | Should -BeTrue
        }

        It "Mentions v07.00 in master orchestrator Comment-Based Help" {
            $match = $MasterContent -match 'Version:\s*v07\.00'
            $match | Should -BeTrue
        }
    }

    Context "Platform Binary Name Resolution" {
        It "Returns .exe binary extension when running on Windows" {
            if ($IsWindows -or ($env:OS -match "Windows")) {
                Get-PlatformBinaryName "ffmpeg" | Should -Be "ffmpeg.exe"
                Get-PlatformBinaryName "curl" | Should -Be "curl.exe"
            }
        }

        It "Returns bare binary name when non-Windows platform is simulated" {
            function global:Test-IsWindowsPlatform { return $false }
            try {
                Get-PlatformBinaryName "ffmpeg" | Should -Be "ffmpeg"
                Get-PlatformBinaryName "curl" | Should -Be "curl"
            } finally {
                # Restore original function
                if ($EngineContent -match '(?ms)function Test-IsWindowsPlatform\s*\{(.+?^\})') {
                    $fnBody = "function global:Test-IsWindowsPlatform { $($Matches[1])"
                    . ([ScriptBlock]::Create($fnBody))
                }
            }
        }
    }

    Context "Hardware Telemetry Schema Integrity" {
        It "Returns all expected hardware telemetry keys from Get-SystemInfo" {
            $sys = Get-SystemInfo
            $sys | Should -Not -BeNullOrEmpty
            $sys.PSObject.Properties.Name | Should -Contain "hostname"
            $sys.PSObject.Properties.Name | Should -Contain "cpu"
            $sys.PSObject.Properties.Name | Should -Contain "ram"
            $sys.PSObject.Properties.Name | Should -Contain "gpu"
            $sys.PSObject.Properties.Name | Should -Contain "motherboard"
            $sys.PSObject.Properties.Name | Should -Contain "bios"
            $sys.PSObject.Properties.Name | Should -Contain "disks"
            $sys.PSObject.Properties.Name | Should -Contain "operating_system"

            $sys.cpu.cores | Should -BeGreaterThan 0
            $sys.ram.total_gb | Should -BeGreaterThan 0
            $sys.gpu.name | Should -Not -BeNullOrEmpty
        }
    }

    Context "Native macOS Service Lifecycle ('native-mlx')" {
        It "Does not invoke Docker CLI inspect when ContainerName is 'native-mlx'" {
            $pConfig = [PSCustomObject]@{
                whisper_service = [PSCustomObject]@{
                    docker_container_name = "native-mlx"
                    api_url = "http://127.0.0.1:9099/asr"
                }
            }
            $meta = Get-WhisperContainerMetadata -PipelineConfig $pConfig
            $meta | Should -Not -BeNullOrEmpty
            $meta.container_name | Should -Be "native-mlx"
        }

        It "Ensure-WhisperContainerRunning skips Docker CLI when container is 'native-mlx'" {
            $pConfig = [PSCustomObject]@{
                whisper_service = [PSCustomObject]@{
                    docker_container_name = "native-mlx"
                    api_url = "http://127.0.0.1:9099/asr"
                    auto_restart_container = $true
                }
            }
            { Ensure-WhisperContainerRunning -PipelineConfig $pConfig } | Should -Not -Throw
        }

        It "Restart-WhisperContainer skips Docker restart when container is 'native-mlx'" {
            $pConfig = [PSCustomObject]@{
                whisper_service = [PSCustomObject]@{
                    docker_container_name = "native-mlx"
                    api_url = "http://127.0.0.1:9099/asr"
                    auto_restart_container = $true
                }
            }
            { Restart-WhisperContainer -PipelineConfig $pConfig } | Should -Not -Throw
        }
    }

    Context "macOS Local Config Layering" {
        It "Correctly deep merges config.local.macos.json.example with default config" {
            $exampleMacPath = Join-Path $PSScriptRoot "..\config\config.local.macos.json.example"
            Test-Path -LiteralPath $exampleMacPath | Should -BeTrue

            $config = Get-PipelineConfig -ExplicitConfigPath $exampleMacPath -ScriptDirectory (Join-Path $PSScriptRoot "..\src")
            $config.whisper_service.docker_container_name | Should -Be "native-mlx"
            $config.whisper_service.model | Should -Be "large-v3"
            $config.ollama_service.model | Should -Be "gemma3:4b"
            $config.lm_studio_service.model | Should -Be "qwen/qwen3.6-35b-a3b"
            $config.profiles.phone | Should -Not -BeNullOrEmpty
            $config.profiles.echoed | Should -Not -BeNullOrEmpty
        }
    }

    Context "Cross-Platform Path Operations" {
        It "Evaluates missing markdown files using Join-Path without literal backslash errors" {
            $tempDir = Join-Path $env:TEMP "mac_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            try {
                $basePath = Join-Path $tempDir "recording_audio"
                $res = Get-MissingMdFiles -BasePath $basePath
                $res.NotesMissing | Should -BeTrue
                $res.SummaryMissing | Should -BeTrue
                $res.GenerateMode | Should -Be "both"

                Set-Content -LiteralPath "$basePath.NOTES.md" -Value "# Notes" -Encoding UTF8
                $res2 = Get-MissingMdFiles -BasePath $basePath
                $res2.NotesMissing | Should -BeFalse
                $res2.SummaryMissing | Should -BeTrue
                $res2.GenerateMode | Should -Be "summary"
            } finally {
                if (Test-Path -LiteralPath $tempDir) {
                    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
