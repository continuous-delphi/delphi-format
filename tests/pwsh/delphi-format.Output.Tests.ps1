# tests/pwsh/delphi-format.Output.Tests.ps1
#
# Exercises the structured-output surface (-Json, -OutputFile, -PassThru) across
# Execute, Check, and WhatIf modes using a cross-platform stub engine. The stub
# simulates a formatting engine so the orchestration is tested without a real
# formatter.exe / radFormatter.exe.
#
# Stub behavior is driven by $env:STUB_MODE:
#   (unset) : leave every file untouched, exit 0        -> "unchanged" / clean
#   format  : append a blank line to each source file   -> "formatted" / dirty (via diff)
#   check   : print "would format: <path>" per source file, exit 1 (radFormatter -check)
#   fail    : exit 2                                     -> engine failure

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'delphi-format.ps1 structured output' {

    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../')).Path
        $script:ToolPath = Join-Path $script:RepoRoot 'source' 'delphi-format.ps1'

        if (-not (Test-Path -LiteralPath $script:ToolPath)) {
            throw "Tool script not found: $script:ToolPath"
        }

        # Build a platform-appropriate stub engine.
        $script:StubDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dfmt-stub-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:StubDir -Force | Out-Null

        if ($IsWindows) {
            $script:StubPath = Join-Path $script:StubDir 'stub-engine.cmd'
            $cmd = @(
                '@echo off'
                'for %%A in (%*) do call :proc "%%~A"'
                'if /I "%STUB_MODE%"=="check" exit /b 1'
                'if /I "%STUB_MODE%"=="fail" exit /b 2'
                'exit /b 0'
                ':proc'
                'set "f=%~1"'
                'set "ext=%~x1"'
                'if /I "%ext%"==".pas" goto act'
                'if /I "%ext%"==".dpr" goto act'
                'if /I "%ext%"==".dpk" goto act'
                'if /I "%ext%"==".dpkw" goto act'
                'if /I "%ext%"==".inc" goto act'
                'goto :eof'
                ':act'
                'if /I "%STUB_MODE%"=="format" echo.>>"%f%"'
                'if /I "%STUB_MODE%"=="check" echo would format: %f%'
                'goto :eof'
            ) -join "`r`n"
            [System.IO.File]::WriteAllText($script:StubPath, $cmd)
        }
        else {
            $script:StubPath = Join-Path $script:StubDir 'stub-engine.sh'
            $sh = @(
                '#!/bin/sh'
                'for a in "$@"; do'
                '  case "$a" in'
                '    *.pas|*.dpr|*.dpk|*.dpkw|*.inc)'
                '      case "$STUB_MODE" in'
                '        format) printf "\n" >> "$a" ;;'
                '        check)  echo "would format: $a" ;;'
                '      esac'
                '      ;;'
                '  esac'
                'done'
                'case "$STUB_MODE" in'
                '  check) exit 1 ;;'
                '  fail)  exit 2 ;;'
                '  *)     exit 0 ;;'
                'esac'
            ) -join "`n"
            [System.IO.File]::WriteAllText($script:StubPath, $sh)
            & chmod '+x' $script:StubPath
        }

        function New-Workspace {
            $ws = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $ws -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $ws 'UnitA.pas') -Value "unit UnitA;`nend." -NoNewline
            Set-Content -LiteralPath (Join-Path $ws 'UnitB.pas') -Value "unit UnitB;`nend." -NoNewline
            return $ws
        }

        function Invoke-Tool {
            param([string]$Mode, [hashtable]$Params)
            if ($Mode) { $env:STUB_MODE = $Mode } else { Remove-Item Env:STUB_MODE -ErrorAction SilentlyContinue }
            $callParams = @{ EnginePath = $script:StubPath } + $Params
            try {
                & $script:ToolPath @callParams
            }
            finally {
                Remove-Item Env:STUB_MODE -ErrorAction SilentlyContinue
            }
        }
    }

    AfterAll {
        Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context '-Json in Execute mode' {

        It 'emits a single valid JSON object' {
            $ws = New-Workspace
            $out = Invoke-Tool -Mode 'format' -Params @{ RootPath = $ws; Json = $true }
            { $out | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'reports Execute mode and per-file formatted status' {
            $ws = New-Workspace
            $result = Invoke-Tool -Mode 'format' -Params @{ RootPath = $ws; Json = $true } | ConvertFrom-Json
            $result.Mode | Should -Be 'Execute'
            $result.FilesScanned | Should -Be 2
            $result.FilesFormatted | Should -Be 2
            $result.FilesUnchanged | Should -Be 0
            @($result.Items | Where-Object { $_.Status -eq 'formatted' }).Count | Should -Be 2
        }

        It 'reports unchanged files when the engine makes no changes' {
            $ws = New-Workspace
            $result = Invoke-Tool -Mode $null -Params @{ RootPath = $ws; Json = $true } | ConvertFrom-Json
            $result.FilesFormatted | Should -Be 0
            $result.FilesUnchanged | Should -Be 2
            @($result.Items | Where-Object { $_.Status -eq 'unchanged' }).Count | Should -Be 2
        }

        It 'suppresses all non-JSON stdout' {
            $ws = New-Workspace
            $out = @(Invoke-Tool -Mode 'format' -Params @{ RootPath = $ws; Json = $true })
            { ($out -join "`n") | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context '-OutputFile' {

        It 'writes the flat CI result object' {
            $ws = New-Workspace
            $outFile = Join-Path $ws 'result.json'
            Invoke-Tool -Mode 'format' -Params @{ RootPath = $ws; OutputFile = $outFile } | Out-Null
            Test-Path -LiteralPath $outFile | Should -BeTrue
            $ci = Get-Content -LiteralPath $outFile -Raw | ConvertFrom-Json
            $ci.engine | Should -Be 'formatter'
            $ci.success | Should -BeTrue
            $ci.exitCode | Should -Be 0
            $ci.filesScanned | Should -Be 2
            $ci.filesFormatted | Should -Be 2
            $ci.PSObject.Properties.Name | Should -Contain 'duration'
        }
    }

    Context '-PassThru' {

        It 'returns the result object to the pipeline' {
            $ws = New-Workspace
            $obj = Invoke-Tool -Mode $null -Params @{ RootPath = $ws; PassThru = $true }
            $obj | Should -Not -BeNullOrEmpty
            $obj.FilesScanned | Should -Be 2
            $obj.Mode | Should -Be 'Execute'
        }
    }

    Context 'Check mode' {

        It 'exits 0 and reports all unchanged when clean (formatter)' {
            $ws = New-Workspace
            $result = Invoke-Tool -Mode $null -Params @{ RootPath = $ws; Check = $true; Json = $true } | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $result.Mode | Should -Be 'Check (no changes)'
            $result.FilesFormatted | Should -Be 0
            $result.FilesUnchanged | Should -Be 2
        }

        It 'exits 1 and marks would-format files when dirty (formatter)' {
            $ws = New-Workspace
            $result = Invoke-Tool -Mode 'format' -Params @{ RootPath = $ws; Check = $true; Json = $true } | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 1
            $result.FilesFormatted | Should -Be 2
            @($result.Items | Where-Object { $_.Status -eq 'would-format' }).Count | Should -Be 2
        }

        It 'does not modify source files' {
            $ws = New-Workspace
            $before = Get-Content -LiteralPath (Join-Path $ws 'UnitA.pas') -Raw
            Invoke-Tool -Mode 'format' -Params @{ RootPath = $ws; Check = $true; Json = $true } | Out-Null
            $after = Get-Content -LiteralPath (Join-Path $ws 'UnitA.pas') -Raw
            $after | Should -Be $before
        }

        It 'parses would-format output from radFormatter -check' {
            $ws = New-Workspace
            $result = Invoke-Tool -Mode 'check' -Params @{ RootPath = $ws; Engine = 'radFormatter'; Check = $true; Json = $true } | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 1
            @($result.Items | Where-Object { $_.Status -eq 'would-format' }).Count | Should -Be 2
        }
    }

    Context 'WhatIf mode' {

        It 'previews changes without modifying files' {
            $ws = New-Workspace
            $before = Get-Content -LiteralPath (Join-Path $ws 'UnitA.pas') -Raw
            $result = Invoke-Tool -Mode 'format' -Params @{ RootPath = $ws; WhatIf = $true; Json = $true } | ConvertFrom-Json
            $result.Mode | Should -Be 'WhatIf (no changes)'
            @($result.Items | Where-Object { $_.Status -eq 'would-format' }).Count | Should -Be 2
            $after = Get-Content -LiteralPath (Join-Path $ws 'UnitA.pas') -Raw
            $after | Should -Be $before
            $LASTEXITCODE | Should -Be 0
        }
    }

    Context 'no source files' {

        It 'emits a valid empty result' {
            $ws = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $ws -Force | Out-Null
            $result = Invoke-Tool -Mode $null -Params @{ RootPath = $ws; Json = $true } | ConvertFrom-Json
            $result.FilesScanned | Should -Be 0
            @($result.Items).Count | Should -Be 0
            $LASTEXITCODE | Should -Be 0
        }
    }
}
