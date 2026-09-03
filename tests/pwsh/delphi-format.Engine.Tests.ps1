# tests/pwsh/delphi-format.Engine.Tests.ps1
#
# Exercises engine discovery (Find-Formatter / Find-RadFormatter resolution
# order), engine dispatch, and engine-specific argument building. The mock
# engine records the exact argument list it receives (via $env:MOCK_ARGS_FILE)
# so the built command line can be asserted without a real formatter.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'delphi-format.ps1 engine discovery and dispatch' {

    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../')).Path
        $script:ToolPath = Join-Path $script:RepoRoot 'source' 'delphi-format.ps1'

        if (-not (Test-Path -LiteralPath $script:ToolPath)) {
            throw "Tool script not found: $script:ToolPath"
        }

        . (Join-Path $PSScriptRoot 'fixtures' 'New-MockEngine.ps1')
        $script:MockEngine = Get-MockEnginePath
        $script:MockDir    = Split-Path $script:MockEngine -Parent
        $script:MockName   = Split-Path $script:MockEngine -Leaf

        function New-Workspace {
            $ws = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $ws -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $ws 'UnitA.pas') -Value "unit UnitA; end."
            return $ws
        }

        # Invokes the tool with MOCK_ARGS_FILE pointed at a temp file, returns
        # the captured argument tokens as a single newline-joined string.
        function Get-EngineArgs {
            param([hashtable]$Params)
            $argsFile = Join-Path $TestDrive ("args-" + [guid]::NewGuid().ToString('N') + ".txt")
            $env:MOCK_ARGS_FILE = $argsFile
            try {
                & $script:ToolPath @Params | Out-Null
            }
            finally {
                Remove-Item Env:MOCK_ARGS_FILE -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $argsFile) { return (Get-Content -LiteralPath $argsFile -Raw) }
            return ''
        }
    }

    Context 'discovery failure' {

        It 'exits 3 when the engine cannot be resolved' {
            $ws = New-Workspace
            $missing = Join-Path $TestDrive 'no-such-engine-xyz.exe'
            & $script:ToolPath -RootPath $ws -EnginePath $missing
            $LASTEXITCODE | Should -Be 3
        }
    }

    Context 'explicit -EnginePath resolution' {

        It 'resolves and runs an engine given by full path' {
            $ws = New-Workspace
            & $script:ToolPath -RootPath $ws -EnginePath $script:MockEngine | Out-Null
            $LASTEXITCODE | Should -Be 0
        }

        It 'resolves a bare engine name via PATH lookup' {
            $ws = New-Workspace
            $savedPath = $env:PATH
            $env:PATH = $script:MockDir + [System.IO.Path]::PathSeparator + $env:PATH
            try {
                & $script:ToolPath -RootPath $ws -EnginePath $script:MockName | Out-Null
                $LASTEXITCODE | Should -Be 0
            }
            finally {
                $env:PATH = $savedPath
            }
        }
    }

    Context 'formatter argument building' {

        It 'always passes -delphi and the source files' {
            $ws = New-Workspace
            $a = Get-EngineArgs -Params @{ RootPath = $ws; EnginePath = $script:MockEngine; Engine = 'formatter' }
            $a | Should -Match '(?m)^-delphi$'
            $a | Should -Match 'UnitA\.pas'
        }

        It 'forwards -config, -e and -b when requested' {
            $ws = New-Workspace
            $a = Get-EngineArgs -Params @{
                RootPath = $ws; EnginePath = $script:MockEngine; Engine = 'formatter'
                EngineConfigFile = 'rules.cfg'; Encoding = 'utf-8'; CreateBackups = $true
            }
            $a | Should -Match '(?m)^-config$'
            $a | Should -Match '(?m)^rules\.cfg$'
            $a | Should -Match '(?m)^-e$'
            $a | Should -Match '(?m)^utf-8$'
            $a | Should -Match '(?m)^-b$'
        }
    }

    Context 'radFormatter argument building' {

        It 'passes -check in check mode and never -delphi' {
            $ws = New-Workspace
            $a = Get-EngineArgs -Params @{
                RootPath = $ws; EnginePath = $script:MockEngine; Engine = 'radFormatter'; Check = $true
            }
            $a | Should -Match '(?m)^-check$'
            $a | Should -Not -Match '(?m)^-delphi$'
        }
    }
}
