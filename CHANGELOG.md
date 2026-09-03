# Changelog

All notable changes to this project will be documented in this file.

---

## [Unreleased]

---

## v0.6.0
- Implement structured output: `-Json` and `-PassThru` now emit a result
  object (per-file status, counts, timing) across Execute/Check/WhatIf, and
  `-OutputFile` writes the flat CI result. `-WhatIf` is now a real preview.
[#1](https://github.com/continuous-delphi/delphi-format/issues/1)

---

## [0.5.0] - Unreleased

Initial release of `delphi-format`.

- Pluggable engine support: `formatter` (RAD Studio) and `radFormatter`
- Configuration file hierarchy with merge semantics
- Check mode for CI validation (`-Check`)
- JSON output (`-Json`) and structured result output (`-OutputFile`)
- File scanning with include/exclude patterns
- WhatIf preview mode
- Version API (`-Version` / `-Version -Format json`)

<br />
<br />

### `delphi-format` - a developer tool from Continuous Delphi

![continuous-delphi logo](https://continuous-delphi.github.io/assets/logos/continuous-delphi-480x270.png)

https://github.com/continuous-delphi