# JSON Output

`delphi-format` can emit its results as structured data in three ways:

- **`-Json`** -- write a single JSON result object to standard output
  (all human-readable text is suppressed).
- **`-PassThru`** -- return the same result as a PowerShell object to the
  pipeline (human-readable text is still written to the host).
- **`-OutputFile <path>`** -- write a flat CI-integration result object to a
  file, for a wrapper (such as the `delphi-powershell-ci` module) to read back.

These are independent and may be combined. `-Version -Format json` and
`-ShowConfig -Json` are documented separately below.

## `-Json` / `-PassThru` result object

The same object shape is produced across all modes (Execute, WhatIf, Check):

```json
{
  "Engine": "formatter",
  "Root": "C:/code/myproject",
  "Mode": "Execute",
  "IncludeFilePattern": ["*.pas", "*.dpr", "*.dpk", "*.dpkw", "*.inc"],
  "ExcludeDirectoryPattern": [".git", ".vs", ".claude"],
  "FilesScanned": 42,
  "FilesFormatted": 7,
  "FilesUnchanged": 35,
  "FilesFailed": 0,
  "DurationMs": 1250,
  "Items": [
    { "Path": "source/Unit1.pas", "Status": "formatted" },
    { "Path": "source/Unit2.pas", "Status": "unchanged" }
  ]
}
```

`-Json` serializes this to stdout; `-PassThru` returns it as a
`[PSCustomObject]` (property names are identical). `Root` and each
`Items[].Path` use forward slashes; `Items[].Path` is relative to `Root`.

### Mode values

| Mode | Description |
|------|-------------|
| `Execute` | Normal run -- files were formatted in place |
| `WhatIf (no changes)` | `-WhatIf` preview -- detects what would change; no files modified |
| `Check (no changes)` | `-Check` audit -- detects what would change; no files modified |

### Status values

| Status | Modes | Description |
|--------|-------|-------------|
| `formatted` | Execute | File content was changed by the engine |
| `unchanged` | all | File was already correctly formatted |
| `would-format` | Check, WhatIf | File needs formatting (none was applied) |
| `failed` | Execute, Check | The engine errored (timeout / non-zero exit) |

### Count semantics

- `FilesScanned` -- total source files considered (after include/exclude filtering).
- `FilesFormatted` -- files that were changed (Execute) **or** would be changed
  (Check / WhatIf, i.e. the `would-format` count).
- `FilesUnchanged` -- files already correctly formatted.
- `FilesFailed` -- files attributed to an engine failure.
- `DurationMs` -- total wall-clock time for the run. Per-file timing is not
  reported: the engine is invoked once over the whole file set, so wall-time
  cannot be honestly attributed to individual files.

### How per-file status is determined

- **Execute** -- the tool hashes each file before and after the engine runs and
  compares; changed files are `formatted`, the rest `unchanged`. If the engine
  reports failure, every file is `failed`.
- **Check / WhatIf** -- files needing formatting are detected without modifying
  anything. `radFormatter` uses its native `-check` flag (the `would format:`
  lines it prints are parsed into `Items`); `formatter.exe`, which has no check
  mode, is run against temp copies and the results diffed against the originals.

## `-OutputFile`

`-OutputFile <path>` writes a flat result object for CI integration:

```json
{
  "engine": "formatter",
  "root": "C:/code/myproject",
  "success": true,
  "exitCode": 0,
  "filesScanned": 42,
  "filesFormatted": 7,
  "filesUnchanged": 35,
  "filesFailed": 0,
  "duration": 1.25
}
```

`duration` is in seconds. `success` is `true` when `exitCode` is 0. The CI
module wrapper (`Invoke-DelphiFormat` in delphi-powershell-ci) reads this file
to build a PowerShell step-result object.

## `-Version -Format json`

```json
{
  "ok": true,
  "command": "version",
  "tool": {
    "name": "delphi-format",
    "version": "0.6.0"
  }
}
```

## `-ShowConfig -Json`

Returns the effective merged orchestration configuration as a JSON object.
Structure matches the supported config keys documented in
[configuration.md](configuration.md).
