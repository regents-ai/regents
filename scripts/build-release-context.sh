#!/usr/bin/env bash
#
# Assemble the parent build context that Dockerfile.dockerignore describes.
#
#   <context>/
#     ash-platform/          this checkout
#     elixir-utils/privy/    the sibling source mix.exs resolves by path
#     mix-cache/             Mix, Hex and rebar3, extracted from the sealed archive
#     npm-cache/_cacache/    the npm content cache
#     rustler-precompiled/   the precompiled native artifact cache
#     esbuild-linux-arm64    the bundler executable
#
# Every input comes from the sealed supply and is checked against its manifest
# first. The script refuses rather than assemble a context it cannot vouch for,
# and it never reaches the network. Re-running it against the same destination
# is safe: the destination is rebuilt from scratch each time.
#
# Usage: scripts/build-release-context.sh <destination> [supply-root]

set -euo pipefail

readonly DEFAULT_SUPPLY_ROOT="/Users/sean/Documents/regent/archive/release-supply"
readonly BASE_SUPPLY="regent-ece.2-20260812"
readonly ESBUILD_SUPPLY="regent-ece.2-esbuild-linux-arm64-0.25.4-20260812"
readonly MIX_SUPPLY="regent-ece.2-mix-hex-rebar-20260812"

usage() {
  printf 'usage: %s <destination> [supply-root]\n' "${0##*/}" >&2
  exit 2
}

die() {
  printf 'refusing: %s\n' "$1" >&2
  exit 1
}

[ $# -ge 1 ] && [ $# -le 2 ] || usage

destination="$1"
supply_root="${2:-$DEFAULT_SUPPLY_ROOT}"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
privy_source="$(cd -- "$repo_root/.." && pwd)/elixir-utils/privy"

base_supply="$supply_root/$BASE_SUPPLY"
esbuild_supply="$supply_root/$ESBUILD_SUPPLY"
mix_supply="$supply_root/$MIX_SUPPLY"
manifest="$base_supply/SUPPLY-MANIFEST.txt"
mix_addendum="$mix_supply/SUPPLY-ADDENDUM.txt"
esbuild_addendum="$esbuild_supply/SUPPLY-ADDENDUM.txt"

for required in "$manifest" "$mix_addendum" "$esbuild_addendum" "$privy_source"; do
  [ -e "$required" ] || die "missing supply input: $required"
done

sha256_of() {
  shasum -a 256 "$1" | cut -d' ' -f1
}

manifest_value() {
  local file="$1" key="$2" value
  value="$(sed -n "s/^${key}=//p" "$file" | head -1)"
  [ -n "$value" ] || die "manifest $file has no $key"
  printf '%s' "$value"
}

expect_sha256() {
  local label="$1" path="$2" expected="$3" actual
  [ -f "$path" ] || die "missing supply input: $path"
  actual="$(sha256_of "$path")"
  [ "$actual" = "$expected" ] ||
    die "$label does not match its manifest
  path:     $path
  expected: $expected
  actual:   $actual"
  printf '  verified %s\n' "$label"
}

printf 'verifying sealed supply\n'

# The npm cache is keyed to one exact lockfile. A drifted lockfile means the
# cache cannot satisfy an offline install, so stop before assembling anything.
expect_sha256 "package-lock.json against the npm cache" \
  "$repo_root/package-lock.json" "$(manifest_value "$manifest" package_lock_sha256)"

expect_sha256 "mix.lock against the Mix cache" \
  "$repo_root/mix.lock" "$(manifest_value "$mix_addendum" mix_lock_sha256)"

expect_sha256 "MIX-CACHE.tar" \
  "$mix_supply/MIX-CACHE.tar" "$(manifest_value "$mix_addendum" archive_sha256)"

expect_sha256 "esbuild-linux-arm64" \
  "$esbuild_supply/esbuild-linux-arm64" \
  "$(manifest_value "$esbuild_addendum" esbuild-linux-arm64.sha256)"

expect_sha256 "$(manifest_value "$manifest" mdex_native_file)" \
  "$base_supply/$(manifest_value "$manifest" mdex_native_file)" \
  "$(manifest_value "$manifest" mdex_native_sha256)"

printf 'assembling context at %s\n' "$destination"

mkdir -p "$(dirname -- "$destination")"
staging="$(mktemp -d "${destination%/}.staging.XXXXXX")"
trap 'chmod -R u+w "$staging" 2>/dev/null || true; rm -rf -- "$staging"' EXIT

mkdir -p "$staging/ash-platform" "$staging/elixir-utils/privy" "$staging/npm-cache"

# The checkout enters whole. Dockerfile.dockerignore, not this script, decides
# what the build may see, and a proof test holds it to that.
rsync -a --exclude '.git' --exclude '_build/' --exclude 'node_modules/' \
  "$repo_root/" "$staging/ash-platform/"
rsync -a --exclude '.git' "$privy_source/" "$staging/elixir-utils/privy/"

# The sealed npm directory is the cache payload itself, so it lands one level
# down: npm resolves its content under <cache>/_cacache.
rsync -a --chmod=u+rwX "$base_supply/npm-cache/" "$staging/npm-cache/_cacache/"
rsync -a --chmod=u+rwX "$base_supply/rustler-precompiled/" "$staging/rustler-precompiled/"

install -m 0755 "$esbuild_supply/esbuild-linux-arm64" "$staging/esbuild-linux-arm64"

# The archive already carries the mix-cache/ prefix.
tar -xf "$mix_supply/MIX-CACHE.tar" -C "$staging"
[ -d "$staging/mix-cache" ] || die "MIX-CACHE.tar did not yield mix-cache/"

install -m 0644 "$repo_root/Dockerfile" "$staging/Dockerfile"
install -m 0644 "$repo_root/Dockerfile.dockerignore" "$staging/Dockerfile.dockerignore"

if [ -e "$destination" ]; then
  chmod -R u+w "$destination"
  rm -rf -- "$destination"
fi
mv "$staging" "$destination"
trap - EXIT

printf 'context ready: %s\n' "$destination"
printf 'build with:\n'
printf '  docker build --network=none --pull=false \\\n'
printf '    -f %s/Dockerfile -t <tag> %s\n' "$destination" "$destination"
