# Engine CLI Reference

Reference for the two formatting engines `delphi-format` orchestrates. This
tool builds engine-specific argument lists and invokes the binary; you normally
do not call these directly, but this documents the underlying CLI surface.

Both engines share these predefined Delphi source extensions:
`*.pas`, `*.dpr`, `*.dpk`, `*.dpkw`, `*.inc`.

---

## formatter.exe (shipped with RAD Studio)

- Ships in `<BDS>\bin\formatter.exe`.
- Removed in Delphi 13 -- only available in Delphi 12 and earlier.
- `delphi-format` always passes `-delphi` to restrict formatting to Delphi
  sources.
- Formatting rules come from `-config <configfile>` (the file managed by the
  RAD Studio IDE under 'Tools > Options > Formatter > Profiles and Status').
- Supports `-d <dir> -r` for recursive directory formatting, but `delphi-format`
  builds an explicit file list and passes files as positional args so that
  excluded directories are respected.
- Has **no** native check/diff mode -- `delphi-format` implements `-Check` for
  this engine by copying each file to a temp location, formatting the copy, and
  diffing against the original (source is never modified).

### Syntax

```
Formatter [<options>][<filename>]...
```

### Options

| Flag | Meaning |
|------|---------|
| `-cpp` | Format only C/C++ sources |
| `-delphi` | Format only Delphi sources |
| `-config <configfile>` | Configuration file (Formatter options; managed via the RAD Studio IDE) |
| `-e <encoding>` | Encoding for reading/writing |
| `-d <directory>` | Directory of files to format (all supported files if no `<filename>` given) |
| `-r` | Format files recursively in `<directory>` and all subdirectories |
| `-b` | Create `.bak` files before formatting |
| `-log <logfile>` | Log file name |
| `-silent` | Do not display error messages |
| `<filename>` | Source file(s), space-separated; wildcards `*` and `?` allowed |

Predefined extensions -- C/C++: `*.cpp, *.cxx, *.cc, *.c, *.hpp, *.hxx, *.hh, *.h`;
Delphi: `*.pas, *.dpr, *.dpk, *.dpkw, *.inc`.

---

## radFormatter.exe (from RAD Programmer)

- Custom formatter, with a native `-check` flag.
- `-check` exits 1 if any file would be changed and 0 if all files are already
  formatted; it modifies nothing and prints one `would format: <path>` line per
  dirty file. `delphi-format` passes `-check` through and parses those lines.
- `-profile <name>` selects a base config profile (exposed by `delphi-format`
  as `-Profile` / the `profile` config key):
  - `Default` -- radFormatter's own default rules
  - `FormatterExe` -- emulates Embarcadero `formatter.exe` behavior
  - `Embarcadero` -- Embarcadero style conventions
  - `NoOp` -- no formatting (useful for testing)
- `-config <configfile>` supplies a JSON rules file. `-writeDefaultConfig <file>`
  generates a fully populated default config and exits (useful for bootstrapping
  a project config). `delphi-format` does not wrap `-writeDefaultConfig` or
  `-trace`.

### Syntax

```
radFormatter [-profile Default|FormatterExe|Embarcadero|NoOp] [-config <configfile>] [-e <encoding>] [-d <directory>] [-r] [-b] [-check] [-trace <dir>] <filename> [<filename> ...]
radFormatter -writeDefaultConfig <configfile>
```

### Options

| Flag | Meaning |
|------|---------|
| `-profile <name>` | Base config profile: `Default`, `FormatterExe`, `Embarcadero`, or `NoOp` |
| `-config <configfile>` | Formatting rules config (JSON) |
| `-e <encoding>` | Encoding for reading/writing |
| `-d <directory>` | Directory of files to format |
| `-r` | Recurse into subdirectories |
| `-b` | Create `.bak` files before formatting |
| `-check` | Exit 1 if any file would change, 0 if all clean; modifies nothing. Prints `would format: <path>` per dirty file |
| `-trace <dir>` | Write per-rule snapshots to `<dir>/` for each formatted file (debugging) |
| `-writeDefaultConfig <configfile>` | Write a fully populated default JSON config and exit |
| `<filename>` | Source file(s), space-separated |

Predefined extensions: `*.pas, *.dpr, *.dpk, *.dpkw, *.inc`.

---

## How delphi-format maps to these flags

| delphi-format | formatter.exe | radFormatter.exe |
|---------------|---------------|------------------|
| (always) | `-delphi` | -- |
| `-EngineConfigFile` | `-config <file>` | `-config <file>` |
| `-Profile` | (ignored -- warns) | `-profile <name>` |
| `-Encoding` | `-e <enc>` | `-e <enc>` |
| `-CreateBackups` | `-b` | `-b` |
| `-Check` | copy-to-temp + diff (no native flag) | `-check` |

See [configuration.md](configuration.md) for the orchestration config keys and
[json-output.md](json-output.md) for the result shape.