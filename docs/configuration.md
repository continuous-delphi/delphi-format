# Configuration

`delphi-format` uses two distinct configuration layers:

1. **Orchestration config** (`delphi-format.json`) -- controls
   delphi-format itself: engine selection, file patterns, output level.
2. **Engine config** (`engineConfigFile` / `-EngineConfigFile`) --
   controls the formatting engine's rules (indentation, spacing, etc.).
   This file is passed to the engine via `-config`.

## Orchestration Config File Hierarchy

```
$HOME/delphi-format.json              lowest priority (user-level defaults)
<ancestors>/delphi-format.json        traversed parents (if searchParentFolders)
<RootPath>/delphi-format.json         project-level (committed to repo)
<RootPath>/delphi-format.local.json   local overrides (gitignored)
-ConfigFile <path>                     explicit CI override
CLI parameters                         highest priority
```

## JSON Format

All keys are optional. Unrecognized keys are ignored.

```json
{
  "engine": "formatter",
  "engineConfigFile": "",
  "encoding": "",
  "createBackups": false,
  "outputLevel": "detailed",
  "includeFilePattern": [],
  "excludeDirectoryPattern": ["vendor*"],
  "searchParentFolders": false,
  "timeoutSeconds": 300
}
```

### Key Descriptions

| Key | Type | Description |
|-----|------|-------------|
| `engine` | string | Formatting engine: `formatter` or `radFormatter` |
| `engineConfigFile` | string | Path to engine-specific formatting rules config |
| `encoding` | string | File encoding passed to engine via `-e` |
| `createBackups` | bool | Create `.bak` files before formatting |
| `outputLevel` | string | Output verbosity: `detailed`, `summary`, `quiet` |
| `includeFilePattern` | array | Additional file patterns beyond defaults |
| `excludeDirectoryPattern` | array | Directory patterns to skip during scanning |
| `searchParentFolders` | bool | Enable upward traversal for monorepo support |
| `timeoutSeconds` | int | Per-engine-invocation timeout |

## Merge Rules

| Type | Behavior |
|------|----------|
| Scalar (string, number, bool) | Last writer wins -- highest-priority source overrides |
| Array | Append + deduplicate by first occurrence across all sources |

## Upward Traversal (Monorepo Support)

When `searchParentFolders` is `true` in a project-level or local config,
the tool walks parent directories collecting `delphi-format.json` files.
Traversal stops when:

1. The filesystem root is reached, or
2. A config file with `"searchParentFolders": false` is found (stop marker)

The file nearest to `-RootPath` has highest priority among traversed files.

## Engine Config File

The `engineConfigFile` key (or `-EngineConfigFile` CLI parameter) points
to the engine's own formatting rules config:

- **formatter.exe**: Config managed by the RAD Studio IDE under
  'Tools > Options > Formatter > Profiles and Status'
- **radFormatter.exe**: JSON config that can be generated with
  `radFormatter -writeDefaultConfig <file>`

This is distinct from the orchestration config. Example:

```json
{
  "engine": "radFormatter",
  "engineConfigFile": "radFormatter.json"
}
```

## `-ShowConfig`

Use `-ShowConfig` to inspect the effective merged configuration:

```powershell
pwsh -File source/delphi-format.ps1 -ShowConfig
pwsh -File source/delphi-format.ps1 -ShowConfig -Json
```

## `-ConfigFile`

Inject an explicit orchestration config file (useful in CI pipelines):

```powershell
pwsh -File source/delphi-format.ps1 -ConfigFile ci/delphi-format-ci.json
```

This file is loaded at the highest priority below CLI parameters.
