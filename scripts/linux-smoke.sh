#!/usr/bin/env bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH= cd -- "${script_dir}/.." && pwd)"

fail() {
  local reason_code="$1"
  local detail="$2"
  printf 'status=fail command=linux-smoke reason_code=%s detail=%s\n' "${reason_code}" "${detail}" >&2
  exit 1
}

if [[ "$(uname -s)" != "Linux" ]]; then
  fail 'LINUX_HOST_REQUIRED' 'run this smoke test on a Linux host or ubuntu-latest runner'
fi

for dependency in git pwsh dotnet helm terraform; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    fail 'LINUX_DEPENDENCY_NOT_AVAILABLE' "required command is missing: ${dependency}"
  fi
done

dotnet_version="$(dotnet --version)"
if [[ "${dotnet_version}" != '10.0.302' ]]; then
  fail 'DOTNET_SDK_VERSION_MISMATCH' "required 10.0.302; detected: ${dotnet_version}"
fi

pwsh_major="$(pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.Major')"
if [[ ! "${pwsh_major}" =~ ^[0-9]+$ ]] || (( pwsh_major < 7 )); then
  fail 'POWERSHELL_CORE_VERSION_UNSUPPORTED' "PowerShell 7 or newer is required; detected major version: ${pwsh_major}"
fi

helm_version="$(helm version --short 2>/dev/null)"
if [[ "${helm_version}" != v3.21.3* ]]; then
  fail 'HELM_VERSION_MISMATCH' "required v3.21.3; detected: ${helm_version}"
fi

terraform_version="$(terraform version | head -n 1)"
if [[ "${terraform_version}" != 'Terraform v1.15.8' ]]; then
  fail 'TERRAFORM_VERSION_MISMATCH' "required Terraform v1.15.8; detected: ${terraform_version}"
fi

for entrypoint in "${script_dir}/task.sh" "${script_dir}/linux-smoke.sh"; do
  if [[ ! -x "${entrypoint}" ]]; then
    fail 'LINUX_ENTRYPOINT_NOT_EXECUTABLE' "tracked executable bit is required: ${entrypoint#"${repo_root}/"}"
  fi
  if LC_ALL=C grep -q $'\r' "${entrypoint}"; then
    fail 'LINUX_ENTRYPOINT_CRLF' "CRLF is forbidden in Linux entrypoint: ${entrypoint#"${repo_root}/"}"
  fi
done

case_collision="$({ git -C "${repo_root}" ls-files | awk '
  {
    folded = tolower($0)
    if ((folded in seen) && seen[folded] != $0) {
      print seen[folded] " <> " $0
      exit
    }
    seen[folded] = $0
  }
'; } || true)"
if [[ -n "${case_collision}" ]]; then
  fail 'LINUX_CASE_COLLISION' "case-sensitive path collision: ${case_collision}"
fi

cd "${repo_root}"
"${script_dir}/task.sh" lint
"${script_dir}/task.sh" test-m0-003

printf '%s\n' 'status=pass command=linux-smoke reason_code=LINUX_ENTRYPOINT_SMOKE_OK'
