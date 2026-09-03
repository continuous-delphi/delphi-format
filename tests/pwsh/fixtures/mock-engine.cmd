@echo off
REM Windows launcher for the mock formatting engine. Forwards all arguments to
REM the PowerShell implementation so delphi-format can invoke it via -EnginePath.
pwsh -NoProfile -File "%~dp0mock-engine.ps1" %*
