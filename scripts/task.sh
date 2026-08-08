#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v pwsh >/dev/null 2>&1; then
  printf '%s\n' 'status=fail reason_code=POWERSHELL_CORE_NOT_AVAILABLE detail=install PowerShell 7 and ensure pwsh is on PATH' >&2
  exit 127
fi

exec pwsh -NoLogo -NoProfile -File "${script_dir}/task.ps1" "$@"
