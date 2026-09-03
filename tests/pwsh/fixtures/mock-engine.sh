#!/bin/sh
# POSIX launcher for the mock formatting engine. Forwards all arguments to the
# PowerShell implementation so delphi-format can invoke it via -EnginePath.
DIR=$(dirname "$0")
exec pwsh -NoProfile -File "$DIR/mock-engine.ps1" "$@"
