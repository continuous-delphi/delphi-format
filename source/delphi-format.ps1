#requires -Version 5.1
# -----------------------------------------------------------------------------
# delphi-format
#
# Delphi source file formatter orchestrator with pluggable engine support.
# Wraps formatter.exe (RAD Studio) and radFormatter.exe behind a unified
# interface with structured output, check mode, and CI integration.
#
# Part of Continuous-Delphi: Focused on strengthening Delphi's continued success
# https://github.com/continuous-delphi
#
# Project repository:
# https://github.com/continuous-delphi/delphi-format
#
# Also included in the Continuous-Delphi PowerShell CI module:
# https://github.com/continuous-delphi/delphi-powershell-ci
#
# Copyright (c) 2026 Darian Miller
# Licensed under the MIT License.
# https://opensource.org/licenses/MIT
# SPDX-License-Identifier: MIT
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
Formats Delphi source files using a pluggable formatting engine.

.DESCRIPTION
Orchestrates a formatting engine (formatter.exe by default) to format
Delphi source files. Supports multiple engines, configuration file
hierarchies, check mode for CI validation, and structured output.

Exit codes:
  0  success (all files formatted or already clean)
  1  check mode found files needing formatting
  2  partial failure (some files failed to format)
  3  fatal error (engine not found, bad root, etc.)

.EXAMPLE
pwsh -File source/delphi-format.ps1

.EXAMPLE
pwsh -File source/delphi-format.ps1 -Engine radFormatter -Check

.EXAMPLE
pwsh -File source/delphi-format.ps1 -Version -Format json
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Format')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
  Justification='Write-Host is intentional: standalone CLI tool streams status to the console host.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'OutputLevel',
  Justification='Consumed by Write-Detail/Write-Summary helper functions.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PassThru',
  Justification='Consumed by tool-specific result reporting logic.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'OutputFile',
  Justification='Consumed by tool-specific result reporting logic.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ExitDirty',
  Justification='Exit code constant used in check mode logic.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Get-DefaultFilePatterns',
  Justification='Patterns is conventional for a collection of glob patterns.')]
param(
    [Parameter(ParameterSetName = 'Version', Mandatory)]
    [switch]$Version,

    [Parameter(ParameterSetName = 'Version')]
    [ValidateSet('text', 'json')]
    [string]$Format = 'text',

    [Parameter(ParameterSetName = 'Format')]
    [ValidateSet('formatter', 'radFormatter')]
    [string]$Engine = 'formatter',

    [Parameter(ParameterSetName = 'Format')]
    [string]$EnginePath,

    [Parameter(ParameterSetName = 'Format')]
    [string]$EngineConfigFile,

    [Parameter(ParameterSetName = 'Format')]
    [string]$RootPath,

    [Parameter(ParameterSetName = 'Format')]
    [string[]]$Path = @(),

    [Parameter(ParameterSetName = 'Format')]
    [string[]]$IncludeFilePattern = @(),

    [Parameter(ParameterSetName = 'Format')]
    [string[]]$ExcludeDirectoryPattern = @(),

    [Parameter(ParameterSetName = 'Format')]
    [string]$Encoding,

    [Parameter(ParameterSetName = 'Format')]
    [switch]$CreateBackups,

    [Parameter(ParameterSetName = 'Format')]
    [ValidateSet('detailed', 'summary', 'quiet')]
    [string]$OutputLevel = 'detailed',

    [Parameter(ParameterSetName = 'Format')]
    [switch]$Json,

    [Parameter(ParameterSetName = 'Format')]
    [switch]$PassThru,

    [Parameter(ParameterSetName = 'Format')]
    [switch]$Check,

    [Parameter(ParameterSetName = 'Format')]
    [switch]$ShowConfig,

    [Parameter(ParameterSetName = 'Format')]
    [string]$ConfigFile,

    [Parameter(ParameterSetName = 'Format')]
    [string]$OutputFile,

    [Parameter(ParameterSetName = 'Format')]
    [int]$TimeoutSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Exit code constants
$ExitSuccess        = 0
$ExitDirty          = 1   # -Check found files needing formatting
$ExitPartialFailure = 2   # some files failed to format
$ExitFatal          = 3   # engine not found, bad root, unhandled error

$script:Version = '0.5.1'

# =============================================================================
# Version info
# =============================================================================

if ($Version) {
    $info = @{
        ok      = $true
        command = 'version'
        tool    = @{
            name    = 'delphi-format'
            version = $script:Version
        }
    }
    if ($Format -eq 'json') {
        Write-Output ($info | ConvertTo-Json -Depth 5 -Compress)
    }
    else {
        Write-Output "delphi-format $($script:Version)"
    }
    exit $ExitSuccess
}

# =============================================================================
# Output helpers
# =============================================================================

$script:SuppressOutput = $Json.IsPresent

function Write-Detail([string]$Message) {
    if ($script:SuppressOutput) { return }
    if ($OutputLevel -eq 'detailed') {
        Write-Host $Message
    }
}

function Write-Summary([string]$Message) {
    if ($script:SuppressOutput) { return }
    if ($OutputLevel -in 'detailed', 'summary') {
        Write-Host $Message
    }
}

function Write-Section([string]$Message) {
    if ($script:SuppressOutput) { return }
    if ($OutputLevel -eq 'detailed') {
        Write-Host ""
        Write-Host $Message -ForegroundColor Cyan
    }
}

function Write-SummarySection([string]$Message) {
    if ($script:SuppressOutput) { return }
    if ($OutputLevel -in 'detailed', 'summary') {
        Write-Host ""
        Write-Host $Message -ForegroundColor Cyan
    }
}

# =============================================================================
# Utility helpers
# =============================================================================

function Format-Duration([double]$Milliseconds) {
    if ($Milliseconds -lt 1000) { return "$([math]::Round($Milliseconds, 0)) ms" }
    return "$([math]::Round($Milliseconds / 1000, 1)) s"
}

function Resolve-ToolRoot([string]$InputPath) {
    if ([string]::IsNullOrEmpty($InputPath)) {
        return (Get-Location).Path
    }
    $resolved = Resolve-Path -LiteralPath $InputPath -ErrorAction SilentlyContinue
    if ($null -eq $resolved) {
        Write-Error "Root path does not exist: $InputPath" -ErrorAction Continue
        exit $ExitFatal
    }
    return $resolved.ProviderPath
}

function Test-SafeRoot([string]$InputPath) {
    $fsRoot = [System.IO.Path]::GetPathRoot($InputPath)
    if ($InputPath -eq $fsRoot) {
        Write-Error "Refusing to operate on the filesystem root: $InputPath" -ErrorAction Continue
        return $false
    }
    return $true
}

function Get-RelativePathCompat([string]$From, [string]$To) {
    $fromUri = [Uri]::new("$From/")
    $toUri   = [Uri]::new($To)
    $rel     = $fromUri.MakeRelativeUri($toUri).ToString()
    return [Uri]::UnescapeDataString($rel) -replace '/', [System.IO.Path]::DirectorySeparatorChar
}

# =============================================================================
# Configuration
# =============================================================================

function Get-ConfigValue([object]$Config, [string]$Key) {
    if ($null -eq $Config) { return $null }
    $props = $Config.PSObject.Properties
    if ($null -eq $props) { return $null }
    $matched = $props.Match($Key)
    if ($matched.Count -gt 0) {
        return $matched[0].Value
    }
    return $null
}

function Read-ConfigFile([string]$FilePath) {
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
        return ($raw | ConvertFrom-Json)
    }
    catch {
        Write-Warning "Failed to parse config file: $FilePath -- $_"
        return $null
    }
}

function Merge-FormatConfig([object]$Base, [object]$Layer) {
    if ($null -eq $Layer) { return $Base }
    if ($null -eq $Base)  { return $Layer }

    # Copy base properties into a fresh object
    $merged = [PSCustomObject]@{}
    foreach ($p in $Base.PSObject.Properties) {
        $merged | Add-Member -MemberType NoteProperty -Name $p.Name -Value $p.Value
    }

    foreach ($prop in $Layer.PSObject.Properties) {
        $key   = $prop.Name
        $value = $prop.Value

        if ($value -is [System.Array]) {
            # Arrays: append + deduplicate
            $existing = Get-ConfigValue $merged $key
            if ($null -ne $existing -and $existing -is [System.Array]) {
                $combined = [System.Collections.Generic.List[string]]::new()
                $seen     = [System.Collections.Generic.HashSet[string]]::new(
                    [StringComparer]::OrdinalIgnoreCase)
                foreach ($item in $existing) {
                    if ($seen.Add($item)) { $combined.Add($item) }
                }
                foreach ($item in $value) {
                    if ($seen.Add($item)) { $combined.Add($item) }
                }
                $merged | Add-Member -MemberType NoteProperty -Name $key -Value $combined.ToArray() -Force
            }
            else {
                $merged | Add-Member -MemberType NoteProperty -Name $key -Value $value -Force
            }
        }
        else {
            # Scalars: last writer wins
            $merged | Add-Member -MemberType NoteProperty -Name $key -Value $value -Force
        }
    }

    return $merged
}

function Resolve-EffectiveConfig([string]$Root, [string]$ExplicitConfigFile) {
    # Start with empty config
    $config = [PSCustomObject]@{}

    # Layer 1: $HOME/delphi-format.json
    $homeDir = if ($env:DELPHI_FORMAT_HOME_OVERRIDE) {
        $env:DELPHI_FORMAT_HOME_OVERRIDE
    } else {
        $HOME
    }
    $homeConfig = Read-ConfigFile (Join-Path $homeDir 'delphi-format.json')
    $config = Merge-FormatConfig $config $homeConfig

    # Layer 2: upward traversal (if searchParentFolders enabled)
    $searchParents = Get-ConfigValue $config 'searchParentFolders'
    # Check project-level config first to see if traversal is enabled
    $projectConfig = Read-ConfigFile (Join-Path $Root 'delphi-format.json')
    $localConfig   = Read-ConfigFile (Join-Path $Root 'delphi-format.local.json')
    if ($null -eq $searchParents) {
        $searchParents = Get-ConfigValue $projectConfig 'searchParentFolders'
    }
    if ($null -eq $searchParents) {
        $searchParents = Get-ConfigValue $localConfig 'searchParentFolders'
    }

    if ($searchParents -eq $true) {
        $parentConfigs = [System.Collections.Generic.List[object]]::new()
        $current = [System.IO.Directory]::GetParent($Root)
        while ($null -ne $current) {
            $parentFile = Join-Path $current.FullName 'delphi-format.json'
            $parentCfg  = Read-ConfigFile $parentFile
            if ($null -ne $parentCfg) {
                $parentConfigs.Add($parentCfg)
                $stop = Get-ConfigValue $parentCfg 'searchParentFolders'
                if ($stop -eq $false) { break }
            }
            $current = $current.Parent
        }
        # Apply from outermost to innermost (innermost wins)
        $parentConfigs.Reverse()
        foreach ($pc in $parentConfigs) {
            $config = Merge-FormatConfig $config $pc
        }
    }

    # Layer 3: project-level config
    $config = Merge-FormatConfig $config $projectConfig

    # Layer 4: local override config
    $config = Merge-FormatConfig $config $localConfig

    # Layer 5: explicit -ConfigFile
    if (-not [string]::IsNullOrEmpty($ExplicitConfigFile)) {
        $explicitCfg = Read-ConfigFile $ExplicitConfigFile
        if ($null -eq $explicitCfg) {
            Write-Error "Config file not found or invalid: $ExplicitConfigFile" -ErrorAction Continue
            exit $ExitFatal
        }
        $config = Merge-FormatConfig $config $explicitCfg
    }

    return $config
}

# =============================================================================
# Engine discovery
# =============================================================================

function Find-Formatter {
    <#
    .SYNOPSIS
        Locates the RAD Studio formatter.exe.
    #>
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrEmpty($ExplicitPath)) {
        if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
            return $ExplicitPath
        }
        $found = Get-Command $ExplicitPath -ErrorAction SilentlyContinue
        if ($null -ne $found) { return $found.Source }
        return $null
    }

    $found = Get-Command 'formatter.exe' -ErrorAction SilentlyContinue
    if ($null -ne $found) { return $found.Source }
    return $null
}

function Find-RadFormatter {
    <#
    .SYNOPSIS
        Locates the radFormatter.exe.
    #>
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrEmpty($ExplicitPath)) {
        if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
            return $ExplicitPath
        }
        $found = Get-Command $ExplicitPath -ErrorAction SilentlyContinue
        if ($null -ne $found) { return $found.Source }
        return $null
    }

    $found = Get-Command 'radFormatter.exe' -ErrorAction SilentlyContinue
    if ($null -ne $found) { return $found.Source }
    return $null
}

# =============================================================================
# File scanning
# =============================================================================

function Get-DefaultFilePatterns {
    return @('*.pas', '*.dpr', '*.dpk', '*.dpkw', '*.inc')
}

function Test-PathUnderExcludedDirectory([string]$FilePath, [string[]]$ExcludePatterns) {
    $builtInExclusions = @('.git', '.vs', '.claude')
    $allExclusions = $builtInExclusions + $ExcludePatterns

    $parts = $FilePath -split '[/\\]'
    foreach ($part in $parts) {
        foreach ($pattern in $allExclusions) {
            if ($part -like $pattern) {
                return $true
            }
        }
    }
    return $false
}

function Get-FilesToFormat([string]$Root, [string[]]$ExplicitPaths, [string[]]$IncludePatterns, [string[]]$ExcludePatterns) {
    $filePatterns = Get-DefaultFilePatterns
    if ($IncludePatterns.Count -gt 0) {
        $filePatterns = $filePatterns + $IncludePatterns
    }
    # Deduplicate
    $filePatterns = $filePatterns | Select-Object -Unique

    $files = [System.Collections.Generic.List[string]]::new()

    if ($ExplicitPaths.Count -gt 0) {
        # Explicit file/directory paths
        foreach ($p in $ExplicitPaths) {
            $resolvedPath = if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $Root $p }
            if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
                foreach ($pattern in $filePatterns) {
                    $found = Get-ChildItem -Path $resolvedPath -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue
                    foreach ($f in $found) {
                        $rel = Get-RelativePathCompat $Root $f.FullName
                        if (-not (Test-PathUnderExcludedDirectory $rel $ExcludePatterns)) {
                            $files.Add($f.FullName)
                        }
                    }
                }
            }
            elseif (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
                $rel = Get-RelativePathCompat $Root $resolvedPath
                if (-not (Test-PathUnderExcludedDirectory $rel $ExcludePatterns)) {
                    $files.Add($resolvedPath)
                }
            }
        }
    }
    else {
        # Scan root directory
        foreach ($pattern in $filePatterns) {
            $found = Get-ChildItem -Path $Root -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue
            foreach ($f in $found) {
                $rel = Get-RelativePathCompat $Root $f.FullName
                if (-not (Test-PathUnderExcludedDirectory $rel $ExcludePatterns)) {
                    $files.Add($f.FullName)
                }
            }
        }
    }

    return $files.ToArray()
}

# =============================================================================
# Engine invocation
# =============================================================================

function Invoke-FormatEngine {
    param(
        [string]$EngineBinary,
        [string]$EngineName,
        [string[]]$SourceFiles,
        [string]$FormatEngineConfigFile,
        [bool]$BackupsEnabled,
        [string]$FileEncoding,
        [bool]$CheckOnly,
        [int]$Timeout
    )

    $engineArgs = [System.Collections.Generic.List[string]]::new()

    if ($EngineName -eq 'formatter') {
        $engineArgs.Add('-delphi')
        # formatter.exe has no check mode -- when $CheckOnly is true
        # the caller uses Invoke-FormatterCheck instead of this function
    }
    if ($EngineName -eq 'radFormatter' -and $CheckOnly) {
        $engineArgs.Add('-check')
    }

    if (-not [string]::IsNullOrEmpty($FormatEngineConfigFile)) {
        $engineArgs.Add('-config')
        $engineArgs.Add($FormatEngineConfigFile)
    }
    if ($BackupsEnabled) { $engineArgs.Add('-b') }
    if (-not [string]::IsNullOrEmpty($FileEncoding)) {
        $engineArgs.Add('-e')
        $engineArgs.Add($FileEncoding)
    }

    foreach ($f in $SourceFiles) { $engineArgs.Add($f) }

    $argsString = $engineArgs -join ' '
    Write-Verbose "Engine: $EngineBinary"
    Write-Verbose "Args: $argsString"

    $proc = Start-Process -FilePath $EngineBinary `
        -ArgumentList $argsString `
        -NoNewWindow -PassThru -Wait:$false
    $exited = $proc.WaitForExit($Timeout * 1000)
    if (-not $exited) {
        try { $proc.Kill() } catch { Write-Verbose "Process already exited: $_" }
        return @{
            Success  = $false
            ExitCode = -1
            Message  = "Formatting engine timed out after ${Timeout}s"
        }
    }

    return @{
        Success  = ($proc.ExitCode -eq 0)
        ExitCode = $proc.ExitCode
        Message  = if ($proc.ExitCode -eq 0) { 'Formatting completed' } else { "Engine exited with code $($proc.ExitCode)" }
    }
}

function Invoke-FormatterCheck {
    <#
    .SYNOPSIS
        Check mode for formatter.exe (which has no native -check flag).
        Copies files to temp, formats the copies, and diffs against originals.
    #>
    param(
        [string]$EngineBinary,
        [string[]]$SourceFiles,
        [string]$FormatEngineConfigFile,
        [string]$FileEncoding,
        [int]$Timeout
    )

    $dirty = [System.Collections.Generic.List[string]]::new()
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "delphi-format-check-$([guid]::NewGuid().ToString('N'))"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    try {
        foreach ($srcFile in $SourceFiles) {
            $tempFile = Join-Path $tempDir ([System.IO.Path]::GetFileName($srcFile))
            Copy-Item -LiteralPath $srcFile -Destination $tempFile -Force

            $engineArgs = [System.Collections.Generic.List[string]]::new()
            $engineArgs.Add('-delphi')
            if (-not [string]::IsNullOrEmpty($FormatEngineConfigFile)) {
                $engineArgs.Add('-config')
                $engineArgs.Add($FormatEngineConfigFile)
            }
            if (-not [string]::IsNullOrEmpty($FileEncoding)) {
                $engineArgs.Add('-e')
                $engineArgs.Add($FileEncoding)
            }
            $engineArgs.Add($tempFile)

            $proc = Start-Process -FilePath $EngineBinary `
                -ArgumentList ($engineArgs -join ' ') `
                -NoNewWindow -PassThru -Wait:$false
            $exited = $proc.WaitForExit($Timeout * 1000)
            if (-not $exited) {
                try { $proc.Kill() } catch { Write-Verbose "Process already exited: $_" }
            }

            if ($proc.ExitCode -eq 0) {
                $original  = Get-Content -LiteralPath $srcFile -Raw -ErrorAction SilentlyContinue
                $formatted = Get-Content -LiteralPath $tempFile -Raw -ErrorAction SilentlyContinue
                if ($original -ne $formatted) {
                    $dirty.Add($srcFile)
                }
            }
        }
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    return @{
        Dirty    = $dirty.ToArray()
        Success  = ($dirty.Count -eq 0)
        ExitCode = if ($dirty.Count -eq 0) { 0 } else { 1 }
        Message  = if ($dirty.Count -eq 0) { 'All files are correctly formatted' } else { "$($dirty.Count) file(s) need formatting" }
    }
}

# =============================================================================
# Main execution
# =============================================================================

try {

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Resolve root path
    $root = Resolve-ToolRoot $RootPath
    if (-not (Test-SafeRoot $root)) {
        exit $ExitFatal
    }

    # Resolve configuration
    $effectiveConfig = Resolve-EffectiveConfig -Root $root -ExplicitConfigFile $ConfigFile

    # Apply CLI overrides to effective config (CLI wins over config files)
    if ($PSBoundParameters.ContainsKey('Engine')) {
        $effectiveConfig | Add-Member -MemberType NoteProperty -Name 'engine' -Value $Engine -Force
    }
    if ($PSBoundParameters.ContainsKey('EngineConfigFile')) {
        $effectiveConfig | Add-Member -MemberType NoteProperty -Name 'engineConfigFile' -Value $EngineConfigFile -Force
    }
    if ($PSBoundParameters.ContainsKey('Encoding')) {
        $effectiveConfig | Add-Member -MemberType NoteProperty -Name 'encoding' -Value $Encoding -Force
    }
    if ($PSBoundParameters.ContainsKey('CreateBackups')) {
        $effectiveConfig | Add-Member -MemberType NoteProperty -Name 'createBackups' -Value $CreateBackups.IsPresent -Force
    }
    if ($PSBoundParameters.ContainsKey('TimeoutSeconds')) {
        $effectiveConfig | Add-Member -MemberType NoteProperty -Name 'timeoutSeconds' -Value $TimeoutSeconds -Force
    }

    # -ShowConfig: display merged config and exit
    if ($ShowConfig) {
        if ($Json) {
            Write-Output ($effectiveConfig | ConvertTo-Json -Depth 5)
        }
        else {
            Write-Host "Effective configuration for: $root"
            Write-Host ($effectiveConfig | ConvertTo-Json -Depth 5)
        }
        exit $ExitSuccess
    }

    # -Check and -WhatIf are mutually exclusive
    if ($Check -and $WhatIfPreference) {
        Write-Error '-Check and -WhatIf cannot be used together.' -ErrorAction Continue
        exit $ExitFatal
    }

    # Resolve effective values from config (CLI overrides already applied)
    $resolvedEngine         = (Get-ConfigValue $effectiveConfig 'engine')          ; if ($null -eq $resolvedEngine)         { $resolvedEngine = $Engine }
    $resolvedEngineConfig   = (Get-ConfigValue $effectiveConfig 'engineConfigFile') ; if ($null -eq $resolvedEngineConfig)   { $resolvedEngineConfig = '' }
    $resolvedEncoding       = (Get-ConfigValue $effectiveConfig 'encoding')         ; if ($null -eq $resolvedEncoding)       { $resolvedEncoding = '' }
    $resolvedBackups        = (Get-ConfigValue $effectiveConfig 'createBackups')    ; if ($null -eq $resolvedBackups)        { $resolvedBackups = $false }
    $resolvedTimeout        = (Get-ConfigValue $effectiveConfig 'timeoutSeconds')   ; if ($null -eq $resolvedTimeout)        { $resolvedTimeout = $TimeoutSeconds }
    $configIncludePatterns  = (Get-ConfigValue $effectiveConfig 'includeFilePattern')
    $configExcludePatterns  = (Get-ConfigValue $effectiveConfig 'excludeDirectoryPattern')

    # Merge CLI patterns with config patterns
    $mergedInclude = @()
    if ($null -ne $configIncludePatterns) { $mergedInclude += $configIncludePatterns }
    if ($IncludeFilePattern.Count -gt 0)  { $mergedInclude += $IncludeFilePattern }
    $mergedExclude = @()
    if ($null -ne $configExcludePatterns) { $mergedExclude += $configExcludePatterns }
    if ($ExcludeDirectoryPattern.Count -gt 0) { $mergedExclude += $ExcludeDirectoryPattern }

    # Discover engine
    $engineBinary = switch ($resolvedEngine) {
        'formatter'    { Find-Formatter    -ExplicitPath $EnginePath }
        'radFormatter' { Find-RadFormatter -ExplicitPath $EnginePath }
    }
    if ($null -eq $engineBinary) {
        Write-Error "Formatting engine '$resolvedEngine' not found. Provide -EnginePath or add it to PATH." -ErrorAction Continue
        exit $ExitFatal
    }

    Write-Section "delphi-format -- $resolvedEngine"

    # Scan for files
    $filesToFormat = Get-FilesToFormat -Root $root -ExplicitPaths $Path -IncludePatterns $mergedInclude -ExcludePatterns $mergedExclude
    Write-Detail "Found $($filesToFormat.Count) source file(s)"

    if ($filesToFormat.Count -eq 0) {
        Write-Summary "No source files found to format."
        $sw.Stop()
        exit $ExitSuccess
    }

    # Execute
    if ($Check) {
        if ($resolvedEngine -eq 'radFormatter') {
            $result = Invoke-FormatEngine -EngineBinary $engineBinary -EngineName $resolvedEngine `
                -SourceFiles $filesToFormat -FormatEngineConfigFile $resolvedEngineConfig `
                -BackupsEnabled $false -FileEncoding $resolvedEncoding `
                -CheckOnly $true -Timeout $resolvedTimeout
        }
        else {
            $result = Invoke-FormatterCheck -EngineBinary $engineBinary `
                -SourceFiles $filesToFormat -FormatEngineConfigFile $resolvedEngineConfig `
                -FileEncoding $resolvedEncoding -Timeout $resolvedTimeout
        }

        $sw.Stop()
        Write-SummarySection $result.Message
        Write-Summary "Completed in $(Format-Duration $sw.Elapsed.TotalMilliseconds)"
        exit $result.ExitCode
    }

    if ($PSCmdlet.ShouldProcess("$($filesToFormat.Count) file(s)", "Format")) {
        $result = Invoke-FormatEngine -EngineBinary $engineBinary -EngineName $resolvedEngine `
            -SourceFiles $filesToFormat -FormatEngineConfigFile $resolvedEngineConfig `
            -BackupsEnabled $resolvedBackups -FileEncoding $resolvedEncoding `
            -CheckOnly $false -Timeout $resolvedTimeout

        $sw.Stop()

        if ($result.Success) {
            Write-SummarySection $result.Message
        }
        else {
            Write-Host ""
            Write-Host "ERROR: $($result.Message)" -ForegroundColor Red
        }

        Write-Summary "Completed in $(Format-Duration $sw.Elapsed.TotalMilliseconds)"

        if (-not $result.Success) {
            exit $ExitPartialFailure
        }
        exit $ExitSuccess
    }

    # WhatIf path
    $sw.Stop()
    Write-Summary "Would format $($filesToFormat.Count) file(s)"
    Write-Summary "Completed in $(Format-Duration $sw.Elapsed.TotalMilliseconds)"
    exit $ExitSuccess

}
catch {
    Write-Error "Fatal error: $_" -ErrorAction Continue
    exit $ExitFatal
}
