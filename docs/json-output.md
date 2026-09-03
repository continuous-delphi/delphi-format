# JSON Output

When `-Json` is active, `delphi-format` emits a single JSON object to
standard output. All other text output is suppressed.

## Output Shape

The same structure is returned across all modes (Execute, WhatIf, Check):

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
    {
      "Path": "source/Unit1.pas",
      "Status": "formatted",
      "DurationMs": 45
    }
  ]
}
```

### Mode Values

| Mode | Description |
|------|-------------|
| `Execute` | Normal run -- files were formatted |
| `WhatIf (no changes)` | Preview mode -- no files modified |
| `Check (no changes)` | Audit mode -- no files modified |

### Status Values

| Status | Description |
|--------|-------------|
| `formatted` | File was modified by the formatter |
| `unchanged` | File was already correctly formatted |
| `failed` | Formatter encountered an error on this file |
| `would-format` | Check/WhatIf mode: file needs formatting |

## `-OutputFile`

When `-OutputFile <path>` is specified, a structured JSON result file is
written for CI integration:

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

The CI module wrapper (`Invoke-DelphiFormat` in delphi-powershell-ci)
uses this file to parse results back into a PowerShell step result object.

## `-Version -Format json`

```json
{
  "ok": true,
  "command": "version",
  "tool": {
    "name": "delphi-format",
    "version": "0.1.0"
  }
}
```

## `-ShowConfig -Json`

Returns the effective merged orchestration configuration as a JSON object.
Structure matches the supported config keys documented in
[configuration.md](configuration.md).
