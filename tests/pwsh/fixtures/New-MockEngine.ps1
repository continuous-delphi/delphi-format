# Dot-source helper: returns the path to the platform-appropriate mock engine
# launcher (see mock-engine.ps1). On non-Windows the .sh launcher is made
# executable at call time so a fresh git checkout (which may not preserve the
# executable bit) still works.

function Get-MockEnginePath {
    [CmdletBinding()]
    param()

    $fixtures = $PSScriptRoot
    if ($IsWindows) {
        return (Join-Path $fixtures 'mock-engine.cmd')
    }

    $sh = Join-Path $fixtures 'mock-engine.sh'
    & chmod '+x' $sh 2>$null
    return $sh
}
