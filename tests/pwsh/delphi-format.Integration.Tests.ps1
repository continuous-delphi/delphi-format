# tests/pwsh/delphi-format.Integration.Tests.ps1
#
# End-to-end orchestration through the fixtures mock engine: Execute / Check /
# WhatIf, exit codes for each mode, structured output, path-with-spaces,
# backups, explicit -Path file mode, and include/exclude scanning. The mock
# engine (fixtures/mock-engine.ps1) treats a file as "needing formatting" iff
# it lacks the sentinel marker line, so the sample .pas fixtures drive
# formatted/unchanged outcomes deterministically.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'delphi-format.ps1 integration' {

    BeforeAll {
        $script:RepoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '../../')).Path
        $script:ToolPath    = Join-Path $script:RepoRoot 'source' 'delphi-format.ps1'
        $script:PasFixtures = Join-Path $PSScriptRoot 'fixtures' 'pas'
        $script:Marker      = '// radformatter: formatted'

        if (-not (Test-Path -LiteralPath $script:ToolPath)) {
            throw "Tool script not found: $script:ToolPath"
        }

        . (Join-Path $PSScriptRoot 'fixtures' 'New-MockEngine.ps1')
        $script:MockEngine = Get-MockEnginePath

        # Creates a workspace seeded with a single Unit1.pas, either the
        # already-formatted fixture (has the marker) or the unformatted one.
        function New-Workspace {
            param([switch]$Formatted, [string]$Name)
            $ws = Join-Path $TestDrive ($Name ? $Name : ([guid]::NewGuid().ToString('N')))
            New-Item -ItemType Directory -Path $ws -Force | Out-Null
            $src = if ($Formatted) { 'Formatted.pas' } else { 'Unformatted.pas' }
            Copy-Item (Join-Path $script:PasFixtures $src) (Join-Path $ws 'Unit1.pas')
            return $ws
        }

        function Invoke-Tool {
            param([hashtable]$Params)
            $callParams = @{ EnginePath = $script:MockEngine } + $Params
            & $script:ToolPath @callParams
        }

        function Test-HasMarker {
            param([string]$Path)
            return ([System.IO.File]::ReadAllText($Path) -like "*$script:Marker*")
        }
    }

    Context 'Execute mode' {

        It 'formats an unformatted file and reports it' {
            $ws = New-Workspace
            $result = Invoke-Tool -Params @{ RootPath = $ws; Json = $true } | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $result.Mode | Should -Be 'Execute'
            $result.FilesFormatted | Should -Be 1
            Test-HasMarker (Join-Path $ws 'Unit1.pas') | Should -BeTrue
        }

        It 'leaves an already-formatted file unchanged' {
            $ws = New-Workspace -Formatted
            $before = [System.IO.File]::ReadAllText((Join-Path $ws 'Unit1.pas'))
            $result = Invoke-Tool -Params @{ RootPath = $ws; Json = $true } | ConvertFrom-Json
            $result.FilesFormatted | Should -Be 0
            $result.FilesUnchanged | Should -Be 1
            [System.IO.File]::ReadAllText((Join-Path $ws 'Unit1.pas')) | Should -Be $before
        }

        It 'exits 2 and marks files failed when the engine fails' {
            $ws = New-Workspace
            $env:MOCK_FAIL = '2'
            try {
                $result = Invoke-Tool -Params @{ RootPath = $ws; Json = $true } | ConvertFrom-Json
            }
            finally {
                Remove-Item Env:MOCK_FAIL -ErrorAction SilentlyContinue
            }
            $LASTEXITCODE | Should -Be 2
            $result.FilesFailed | Should -Be 1
        }
    }

    Context 'Check mode exit codes' {

        It 'exits 1 on a dirty tree (formatter copy/diff)' {
            $ws = New-Workspace
            Invoke-Tool -Params @{ RootPath = $ws; Check = $true } | Out-Null
            $LASTEXITCODE | Should -Be 1
            Test-HasMarker (Join-Path $ws 'Unit1.pas') | Should -BeFalse   # never modified
        }

        It 'exits 0 on a clean tree' {
            $ws = New-Workspace -Formatted
            Invoke-Tool -Params @{ RootPath = $ws; Check = $true } | Out-Null
            $LASTEXITCODE | Should -Be 0
        }

        It 'exits 1 on a dirty tree via radFormatter -check' {
            $ws = New-Workspace
            $result = Invoke-Tool -Params @{ RootPath = $ws; Engine = 'radFormatter'; Check = $true; Json = $true } | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 1
            @($result.Items | Where-Object { $_.Status -eq 'would-format' }).Count | Should -Be 1
        }
    }

    Context 'WhatIf mode' {

        It 'previews without modifying and exits 0' {
            $ws = New-Workspace
            $result = Invoke-Tool -Params @{ RootPath = $ws; WhatIf = $true; Json = $true } | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $result.Mode | Should -Be 'WhatIf (no changes)'
            Test-HasMarker (Join-Path $ws 'Unit1.pas') | Should -BeFalse
        }
    }

    Context 'structured output' {

        It '-Json emits the documented shape' {
            $ws = New-Workspace
            $result = Invoke-Tool -Params @{ RootPath = $ws; Json = $true } | ConvertFrom-Json
            $result.Engine | Should -Be 'formatter'
            $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
            $result.PSObject.Properties.Name | Should -Contain 'Items'
            $result.FilesScanned | Should -Be 1
        }

        It '-PassThru returns an object to the pipeline' {
            $ws = New-Workspace
            $obj = Invoke-Tool -Params @{ RootPath = $ws; PassThru = $true }
            $obj.FilesScanned | Should -Be 1
            $obj.Mode | Should -Be 'Execute'
        }

        It '-OutputFile writes the flat CI result' {
            $ws = New-Workspace
            $outFile = Join-Path $ws 'result.json'
            Invoke-Tool -Params @{ RootPath = $ws; OutputFile = $outFile } | Out-Null
            $ci = Get-Content -LiteralPath $outFile -Raw | ConvertFrom-Json
            $ci.success | Should -BeTrue
            $ci.filesFormatted | Should -Be 1
            $ci.PSObject.Properties.Name | Should -Contain 'duration'
        }
    }

    Context 'output levels' {

        # Progress output uses Write-Host (information stream), so capture 6>&1.
        It '-OutputLevel quiet prints nothing' {
            $ws = New-Workspace
            $out = @(& $script:ToolPath -EnginePath $script:MockEngine -RootPath $ws -OutputLevel quiet 6>&1)
            $out.Count | Should -Be 0
        }

        It '-OutputLevel detailed prints progress' {
            $ws = New-Workspace
            $out = @(& $script:ToolPath -EnginePath $script:MockEngine -RootPath $ws -OutputLevel detailed 6>&1)
            $out.Count | Should -BeGreaterThan 0
        }
    }

    Context 'path with spaces' {

        It 'formats a file under a directory whose name contains a space' {
            $ws  = New-Workspace -Name ('space dir ' + [guid]::NewGuid().ToString('N'))
            Invoke-Tool -Params @{ RootPath = $ws } | Out-Null
            $LASTEXITCODE | Should -Be 0
            Test-HasMarker (Join-Path $ws 'Unit1.pas') | Should -BeTrue
        }
    }

    Context 'backups' {

        It '-CreateBackups writes a .bak alongside the formatted file' {
            $ws = New-Workspace
            Invoke-Tool -Params @{ RootPath = $ws; CreateBackups = $true } | Out-Null
            Test-Path -LiteralPath (Join-Path $ws 'Unit1.pas.bak') | Should -BeTrue
        }
    }

    Context 'explicit -Path file mode' {

        It 'formats only the named file' {
            $ws = New-Workspace
            Copy-Item (Join-Path $script:PasFixtures 'Unformatted.pas') (Join-Path $ws 'Unit2.pas')
            Invoke-Tool -Params @{ RootPath = $ws; Path = @('Unit1.pas') } | Out-Null
            Test-HasMarker (Join-Path $ws 'Unit1.pas') | Should -BeTrue
            Test-HasMarker (Join-Path $ws 'Unit2.pas') | Should -BeFalse
        }
    }

    Context 'scan filtering' {

        It 'skips files under an excluded directory' {
            $ws = New-Workspace
            $vendor = Join-Path $ws 'vendor'
            New-Item -ItemType Directory -Path $vendor -Force | Out-Null
            Copy-Item (Join-Path $script:PasFixtures 'Unformatted.pas') (Join-Path $vendor 'Skip.pas')

            $result = Invoke-Tool -Params @{ RootPath = $ws; ExcludeDirectoryPattern = @('vendor*'); Json = $true } | ConvertFrom-Json
            $result.FilesScanned | Should -Be 1
            Test-HasMarker (Join-Path $vendor 'Skip.pas') | Should -BeFalse
        }

        It 'includes an extra pattern supplied via -IncludeFilePattern' {
            $ws = New-Workspace
            Set-Content -LiteralPath (Join-Path $ws 'Extra.pp') -Value 'unit Extra; end.'
            $result = Invoke-Tool -Params @{ RootPath = $ws; IncludeFilePattern = @('*.pp'); Json = $true } | ConvertFrom-Json
            $result.FilesScanned | Should -Be 2
            @($result.Items | Where-Object { $_.Path -like '*Extra.pp' }).Count | Should -Be 1
        }
    }
}
