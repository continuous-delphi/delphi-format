# Changelog

All notable changes to this project will be documented in this file.

---

## [Unreleased]

---

## v0.6.3
- Add `-Profile` parameter and `profile` config key to select radFormatter's
  base config profile (`Default`, `FormatterExe`, `Embarcadero`, `NoOp`),
  forwarded to radFormatter via `-profile` in both format and check runs. It is
  radFormatter-only and never passed to `formatter.exe`.
[#4](https://github.com/continuous-delphi/delphi-format/issues/4)

---

## v0.6.2
- Add the Config, Engine, and Integration Pester suites plus a `tests/pwsh/fixtures/`
  mock engine (formatter/radFormatter simulation), config fixtures, and sample
  `.pas` files. Covers the config hierarchy/merge rules, engine discovery and
  dispatch, and end-to-end Execute/Check/WhatIf/output modes (57 tests pass).
[#2](https://github.com/continuous-delphi/delphi-format/issues/2)
- Fix `Merge-FormatConfig` silently dropping earlier array values when the
  accumulated array held a single element (single-element arrays unrolled to a
  scalar on return, defeating the append/dedupe path).
[#5](https://github.com/continuous-delphi/delphi-format/issues/5)

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