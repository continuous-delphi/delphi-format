# delphi-format

[![CI](https://github.com/continuous-delphi/delphi-format/actions/workflows/ci.yml/badge.svg)](https://github.com/continuous-delphi/delphi-format/actions/workflows/ci.yml)

A PowerShell utility for formatting Delphi source files using pluggable
formatting engines. Wraps `formatter.exe` (RAD Studio, pre-Delphi 13) and
`radFormatter.exe` behind a unified interface with structured output,
check mode, and CI integration.

Part of [Continuous-Delphi](https://github.com/continuous-delphi):
Focused on strengthening Delphi's continued success.

---

## Quick Start

```powershell
# Format using RAD Studio formatter (default engine)
pwsh -File source/delphi-format.ps1

# Format using radFormatter
pwsh -File source/delphi-format.ps1 -Engine radFormatter

# CI validation: fail if any files need formatting
pwsh -File source/delphi-format.ps1 -Check -OutputLevel quiet

# Preview what would be formatted
pwsh -File source/delphi-format.ps1 -WhatIf
```

---

## Supported Engines

| Engine | Binary | Notes |
|--------|--------|-------|
| `formatter` (default) | `formatter.exe` | RAD Studio built-in. Removed in Delphi 13. |
| `radFormatter` | `radFormatter.exe` | RAD Programmer formatter with native `-check` support. |

---

## Parameters

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `-Engine` | string | `formatter` | Formatting engine: `formatter` or `radFormatter` |
| `-EnginePath` | string | | Explicit path to engine binary |
| `-EngineConfigFile` | string | | Engine-specific formatting rules config file |
| `-Profile` | string | | radFormatter base config profile: `Default`, `FormatterExe`, `Embarcadero`, `NoOp` (radFormatter only; ignored by `formatter`) |
| `-RootPath` | string | current directory | Root directory to scan for source files |
| `-Path` | string[] | | Specific file(s) or directory(ies) to format |
| `-IncludeFilePattern` | string[] | | Additional file patterns beyond defaults |
| `-ExcludeDirectoryPattern` | string[] | | Directory patterns to skip during scanning |
| `-Encoding` | string | | File encoding passed to engine via `-e` |
| `-CreateBackups` | switch | | Create `.bak` files before formatting |
| `-OutputLevel` | string | `detailed` | Output verbosity: `detailed`, `summary`, `quiet` |
| `-Json` | switch | | Emit JSON output instead of plain text |
| `-PassThru` | switch | | Return objects to pipeline |
| `-Check` | switch | | Audit-only mode (exit 1 if files need formatting) |
| `-WhatIf` | switch | | Preview mode (no changes made) |
| `-ShowConfig` | switch | | Display merged configuration and exit |
| `-ConfigFile` | string | | Explicit delphi-format.json config file path |
| `-OutputFile` | string | | Write structured JSON result for CI integration |
| `-TimeoutSeconds` | int | `300` | Per-engine-invocation timeout |
| `-Version` | switch | | Display tool version and exit |
| `-Format` | string | `text` | Output format for `-Version`: `text` or `json` |

### Default File Patterns

Both engines format: `*.pas`, `*.dpr`, `*.dpk`, `*.dpkw`, `*.inc`

Use `-IncludeFilePattern` to add additional patterns.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (all files formatted or already clean) |
| 1 | Check mode found files needing formatting |
| 2 | Partial failure (some files failed to format) |
| 3 | Fatal error (engine not found, bad root, etc.) |

---

## Configuration

Two distinct configuration layers:

1. **Orchestration config** (`delphi-format.json`) -- controls
   delphi-format itself: engine selection, file patterns, output level.
2. **Engine config** (`-EngineConfigFile`) -- controls the formatting
   engine's rules: indentation, spacing, brace placement, etc.

### Orchestration Config Hierarchy

```
$HOME/delphi-format.json              (user-level defaults)
<RootPath>/delphi-format.json         (project-level, committed)
<RootPath>/delphi-format.local.json   (local overrides, gitignored)
-ConfigFile <path>                     (explicit CI override)
CLI parameters                         (highest priority)
```

See [docs/configuration.md](docs/configuration.md) for merge rules and
monorepo support.

---

## Structured Output

`-Json`, `-PassThru`, and `-OutputFile` emit a structured result (per-file
status, counts, and timing) for Execute, Check, and WhatIf modes. See
[docs/json-output.md](docs/json-output.md) for the full object shape and
field semantics.

---

## Examples

```powershell
# Format with explicit engine path
pwsh -File source/delphi-format.ps1 -Engine radFormatter -EnginePath C:\tools\radFormatter.exe

# Format with engine-specific config
pwsh -File source/delphi-format.ps1 -EngineConfigFile radFormatter.json

# Select a radFormatter base profile
pwsh -File source/delphi-format.ps1 -Engine radFormatter -Profile FormatterExe

# Format specific directory
pwsh -File source/delphi-format.ps1 -Path source/

# Exclude directories
pwsh -File source/delphi-format.ps1 -ExcludeDirectoryPattern 'vendor*','thirdparty'

# Create backups before formatting
pwsh -File source/delphi-format.ps1 -CreateBackups

# JSON output for CI
pwsh -File source/delphi-format.ps1 -Json

# Show merged configuration
pwsh -File source/delphi-format.ps1 -ShowConfig -Json

# Version info
pwsh -File source/delphi-format.ps1 -Version -Format json
```

---

## Running Tests

```powershell
# Requires: PowerShell 7+, Pester 5.7+, PSScriptAnalyzer
Install-Module Pester -MinimumVersion 5.7.0 -Force -Scope CurrentUser
Install-Module PSScriptAnalyzer -Force -Scope CurrentUser

pwsh tests/run-tests.ps1
```

---

## Also Included In

The [Continuous-Delphi PowerShell CI module](https://github.com/continuous-delphi/delphi-powershell-ci)
bundles `delphi-format` as a pipeline action.

---

<br />

### `delphi-format` - a developer tool from Continuous Delphi

![continuous-delphi logo](https://continuous-delphi.github.io/assets/logos/continuous-delphi-480x270.png)

https://github.com/continuous-delphi