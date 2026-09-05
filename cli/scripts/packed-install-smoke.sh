#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
package_dir="${repo_root}/packages/regents-cli"
smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/regents-cli-pack-smoke.XXXXXX")"
trap 'rm -rf "${smoke_dir}"' EXIT

tarball="$(cd "${package_dir}" && pnpm pack --pack-destination "${smoke_dir}" | tail -n 1)"
if [[ "${tarball}" != /* ]]; then
  tarball="${smoke_dir}/${tarball}"
fi
if [[ ! -f "${tarball}" ]]; then
  echo "packed CLI tarball was not created: ${tarball}" >&2
  exit 1
fi

tar -xzf "${tarball}" -C "${smoke_dir}"
ln -s "${package_dir}/node_modules" "${smoke_dir}/package/node_modules"

output="$(
  cd "${smoke_dir}"
  node package/dist/index.js techtree forge family show --json
)"

node -e '
const value = JSON.parse(process.argv[1]);
if (
  value.family_id !== "techtree.contract-drift-repair.v1" ||
  value.executor !== "hermes" ||
  value.intervention?.artifact !== "SKILL.md" ||
  value.intervention?.changed_file_count !== 1
) {
  throw new Error("packed Forge family output did not match the closed contract");
}
' "${output}"

printf 'Packed CLI Forge family smoke passed.\n'
