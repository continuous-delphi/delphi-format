#requires -Version 5.1
# -----------------------------------------------------------------------------
# Mock formatting engine for delphi-format tests.
#
# Simulates formatter.exe / radFormatter.exe without a real Delphi install so
# the Pester suite exercises orchestration, not the engine. A source file is
# considered to "need formatting" iff it does NOT already contain the sentinel
# marker line. This makes the notion of formatted/unformatted independent of
# line endings (substring test), so CRLF-normalized fixtures behave the same as
# LF ones.
#
# Behavior by flag:
#   -check        : report "would format: <path>" per dirty file, exit 1 if any
#                   dirty (0 if clean); never modifies files (radFormatter mode).
#   (no -check)   : append the marker to each dirty file (idempotent), exit 0.
#   -b            : copy <path> to <path>.bak before modifying it.
#   -config <f>   : accepted and ignored (value skipped).
#   -e <enc>      : accepted and ignored (value skipped).
#   -profile <p>  : accepted and ignored (value skipped).
#   -delphi / -r  : accepted and ignored.
#
# Diagnostics: if $env:MOCK_ARGS_FILE is set, the full received argument list is
# written there (one token per line) so tests can assert engine-specific
# argument building.
# -----------------------------------------------------------------------------

param()

$ErrorActionPreference = 'Stop'

$rawArgs = @($args)
if ($env:MOCK_ARGS_FILE) {
    [System.IO.File]::WriteAllText($env:MOCK_ARGS_FILE, ($rawArgs -join "`n"))
}

# Failure injection for exit-code tests: exit immediately with the requested
# code without touching any files.
if ($env:MOCK_FAIL) { exit [int]$env:MOCK_FAIL }

$marker    = '// radformatter: formatted'
$checkMode = $false
$backup    = $false
$files     = [System.Collections.Generic.List[string]]::new()

for ($i = 0; $i -lt $rawArgs.Count; $i++) {
    $a = [string]$rawArgs[$i]
    switch -Regex ($a) {
        '^-check$'   { $checkMode = $true }
        '^-b$'       { $backup = $true }
        '^-config$'  { $i++ }   # skip the value token
        '^-e$'       { $i++ }   # skip the encoding value
        '^-profile$' { $i++ }   # skip the profile value
        '^-'         { }        # -delphi, -r, or any other flag: ignore
        default      { $files.Add($a) }
    }
}

$exts  = @('.pas', '.dpr', '.dpk', '.dpkw', '.inc')
$dirty = $false

foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
    $ext = [System.IO.Path]::GetExtension($f).ToLowerInvariant()
    if ($exts -notcontains $ext) { continue }

    $content = [System.IO.File]::ReadAllText($f)
    $needs   = ($content -notlike "*$marker*")
    if (-not $needs) { continue }

    $dirty = $true
    if ($checkMode) {
        Write-Output "would format: $f"
        continue
    }

    if ($backup) { [System.IO.File]::Copy($f, "$f.bak", $true) }

    $newContent = $content
    if ($newContent.Length -gt 0 -and -not $newContent.EndsWith("`n")) { $newContent += "`n" }
    $newContent += "$marker`n"
    [System.IO.File]::WriteAllText($f, $newContent)
}

if ($checkMode -and $dirty) { exit 1 }
exit 0
