# tests/pwsh/delphi-format.Config.Tests.ps1
#
# Exercises the orchestration-config resolution surface: the layered hierarchy
# ($HOME -> traversed parents -> project -> local -> -ConfigFile -> CLI), the
# merge rules (scalar last-writer-wins, array append + case-insensitive dedupe),
# searchParentFolders traversal + stop marker, and -ShowConfig output. The
# engine binary is never invoked here -- every case runs through -ShowConfig.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'delphi-format.ps1 configuration' {

    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../')).Path
        $script:ToolPath = Join-Path $script:RepoRoot 'source' 'delphi-format.ps1'
        $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
        $script:Configs  = Join-Path $script:Fixtures 'configs'

        if (-not (Test-Path -LiteralPath $script:ToolPath)) {
            throw "Tool script not found: $script:ToolPath"
        }

        # Safe property lookup: StrictMode makes $obj.Missing throw, but indexing
        # PSObject.Properties by an absent name returns $null.
        function Get-Val {
            param([object]$Object, [string]$Key)
            $p = $Object.PSObject.Properties[$Key]
            if ($p) { return $p.Value }
            return $null
        }

        function New-Dir {
            param([string]$Path)
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            return $Path
        }

        # Runs -ShowConfig -Json against $Root with $HomeDir as the fake $HOME
        # and returns the parsed effective config.
        function Get-EffectiveConfig {
            param([string]$Root, [string]$HomeDir, [string]$ConfigFile)
            if (-not $HomeDir) { $HomeDir = New-Dir (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) }
            $env:DELPHI_FORMAT_HOME_OVERRIDE = $HomeDir
            try {
                $p = @{ ShowConfig = $true; Json = $true; RootPath = $Root }
                if ($ConfigFile) { $p.ConfigFile = $ConfigFile }
                $out = & $script:ToolPath @p
                return ($out | ConvertFrom-Json)
            }
            finally {
                Remove-Item Env:DELPHI_FORMAT_HOME_OVERRIDE -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'home + project merge' {

        It 'lets the project config win scalars and appends arrays' {
            # NB: do not name this $home -- that shadows the read-only automatic $HOME.
            $homeDir = New-Dir (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            $ws      = New-Dir (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            Copy-Item (Join-Path $script:Configs 'user-level-example.json') (Join-Path $homeDir 'delphi-format.json')
            Copy-Item (Join-Path $script:Configs 'project-example.json')    (Join-Path $ws 'delphi-format.json')

            $cfg = Get-EffectiveConfig -Root $ws -HomeDir $homeDir

            # Scalars: project (higher priority) wins.
            (Get-Val $cfg 'engine')         | Should -Be 'radFormatter'
            (Get-Val $cfg 'timeoutSeconds') | Should -Be 120
            (Get-Val $cfg 'outputLevel')    | Should -Be 'summary'

            # Arrays: append across layers (home first, then project).
            $inc = @(Get-Val $cfg 'includeFilePattern')
            $inc | Should -Contain '*.lpr'
            $inc | Should -Contain '*.pp'
            $exc = @(Get-Val $cfg 'excludeDirectoryPattern')
            $exc | Should -Contain 'thirdparty*'
            $exc | Should -Contain 'vendor*'
        }
    }

    Context 'array de-duplication' {

        It 'dedupes repeated patterns case-insensitively across layers' {
            $ws = New-Dir (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            Set-Content -LiteralPath (Join-Path $ws 'delphi-format.json') `
                -Value '{ "excludeDirectoryPattern": ["vendor*", "dist*"] }'
            Set-Content -LiteralPath (Join-Path $ws 'delphi-format.local.json') `
                -Value '{ "excludeDirectoryPattern": ["VENDOR*", "build*"] }'

            $cfg = Get-EffectiveConfig -Root $ws
            $exc = @(Get-Val $cfg 'excludeDirectoryPattern')

            @($exc | Where-Object { $_ -ieq 'vendor*' }).Count | Should -Be 1
            $exc | Should -Contain 'dist*'
            $exc | Should -Contain 'build*'
        }
    }

    Context '-ConfigFile explicit override' {

        It 'wins scalars over the project config' {
            $ws = New-Dir (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            Set-Content -LiteralPath (Join-Path $ws 'delphi-format.json') `
                -Value '{ "engine": "formatter", "timeoutSeconds": 300 }'
            $ci = Join-Path $ws 'ci-config.json'
            Set-Content -LiteralPath $ci -Value '{ "engine": "radFormatter", "timeoutSeconds": 90 }'

            $cfg = Get-EffectiveConfig -Root $ws -ConfigFile $ci
            (Get-Val $cfg 'engine')         | Should -Be 'radFormatter'
            (Get-Val $cfg 'timeoutSeconds') | Should -Be 90
        }

        It 'exits 3 when the -ConfigFile path is invalid' {
            $ws = New-Dir (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            & $script:ToolPath -ShowConfig -RootPath $ws -ConfigFile (Join-Path $ws 'missing.json')
            $LASTEXITCODE | Should -Be 3
        }
    }

    Context 'searchParentFolders traversal' {

        It 'collects an ancestor config when enabled' {
            $anc  = New-Dir (Join-Path $TestDrive ("mono-" + [guid]::NewGuid().ToString('N')))
            $leaf = New-Dir (Join-Path $anc 'app')
            Set-Content -LiteralPath (Join-Path $anc 'delphi-format.json') `
                -Value '{ "searchParentFolders": true, "excludeDirectoryPattern": ["anc-lvl"] }'
            Set-Content -LiteralPath (Join-Path $leaf 'delphi-format.json') `
                -Value '{ "searchParentFolders": true, "excludeDirectoryPattern": ["leaf-lvl"] }'

            $cfg = Get-EffectiveConfig -Root $leaf
            $exc = @(Get-Val $cfg 'excludeDirectoryPattern')
            $exc | Should -Contain 'anc-lvl'
            $exc | Should -Contain 'leaf-lvl'
        }

        It 'stops at a parent marked searchParentFolders:false' {
            $top  = New-Dir (Join-Path $TestDrive ("stop-" + [guid]::NewGuid().ToString('N')))
            $mid  = New-Dir (Join-Path $top 'mid')
            $leaf = New-Dir (Join-Path $mid 'leaf')
            Set-Content -LiteralPath (Join-Path $top 'delphi-format.json') `
                -Value '{ "excludeDirectoryPattern": ["top-lvl"] }'
            Set-Content -LiteralPath (Join-Path $mid 'delphi-format.json') `
                -Value '{ "searchParentFolders": false, "excludeDirectoryPattern": ["mid-lvl"] }'
            Set-Content -LiteralPath (Join-Path $leaf 'delphi-format.json') `
                -Value '{ "searchParentFolders": true, "excludeDirectoryPattern": ["leaf-lvl"] }'

            $cfg = Get-EffectiveConfig -Root $leaf
            $exc = @(Get-Val $cfg 'excludeDirectoryPattern')
            $exc | Should -Contain 'leaf-lvl'
            $exc | Should -Contain 'mid-lvl'
            $exc | Should -Not -Contain 'top-lvl'
        }

        It 'ignores ancestors when searchParentFolders is absent (default off)' {
            $anc  = New-Dir (Join-Path $TestDrive ("noparent-" + [guid]::NewGuid().ToString('N')))
            $leaf = New-Dir (Join-Path $anc 'app')
            Set-Content -LiteralPath (Join-Path $anc 'delphi-format.json') `
                -Value '{ "excludeDirectoryPattern": ["anc-lvl"] }'
            Set-Content -LiteralPath (Join-Path $leaf 'delphi-format.json') `
                -Value '{ "excludeDirectoryPattern": ["leaf-lvl"] }'

            $cfg = Get-EffectiveConfig -Root $leaf
            $exc = @(Get-Val $cfg 'excludeDirectoryPattern')
            $exc | Should -Contain 'leaf-lvl'
            $exc | Should -Not -Contain 'anc-lvl'
        }
    }

    Context 'profile config key' {

        It 'surfaces the profile config key in the effective config' {
            $ws = New-Dir (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            Set-Content -LiteralPath (Join-Path $ws 'delphi-format.json') -Value '{ "profile": "Embarcadero" }'
            $cfg = Get-EffectiveConfig -Root $ws
            (Get-Val $cfg 'profile') | Should -Be 'Embarcadero'
        }

        It 'lets CLI -Profile override the config profile' {
            $ws = New-Dir (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            Set-Content -LiteralPath (Join-Path $ws 'delphi-format.json') -Value '{ "profile": "Embarcadero" }'
            $env:DELPHI_FORMAT_HOME_OVERRIDE = (New-Dir (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))))
            try {
                $cfg = & $script:ToolPath -ShowConfig -Json -RootPath $ws -Profile NoOp | ConvertFrom-Json
                (Get-Val $cfg 'profile') | Should -Be 'NoOp'
            }
            finally {
                Remove-Item Env:DELPHI_FORMAT_HOME_OVERRIDE -ErrorAction SilentlyContinue
            }
        }
    }

    Context '-ShowConfig text output' {

        It 'exits 0 and prints the resolved root' {
            $ws = New-Dir (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
            Set-Content -LiteralPath (Join-Path $ws 'delphi-format.json') -Value '{ "engine": "formatter" }'
            $env:DELPHI_FORMAT_HOME_OVERRIDE = (New-Dir (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))))
            try {
                # -ShowConfig text output uses Write-Host (information stream); merge 6>&1 to capture it.
                $out = & $script:ToolPath -ShowConfig -RootPath $ws 6>&1
                $LASTEXITCODE | Should -Be 0
                ($out -join "`n") | Should -BeLike '*Effective configuration for*'
            }
            finally {
                Remove-Item Env:DELPHI_FORMAT_HOME_OVERRIDE -ErrorAction SilentlyContinue
            }
        }
    }
}
