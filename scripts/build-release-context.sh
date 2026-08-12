#!/usr/bin/env bash
#
# Assemble the parent build context that Dockerfile.dockerignore describes.
#
#   <context>/
#     ash-platform/            this checkout
#     design-system/regent_ui/ the sibling source mix.exs resolves by path
#     elixir-utils/privy/      the sibling source mix.exs resolves by path
#     mix-cache/               Mix, Hex and rebar3, extracted from the sealed archive
#     npm-cache/_cacache/      the npm content cache
#     rustler-precompiled/     the precompiled native artifact, one per target
#                              architecture
#     esbuild-linux-arm64      the bundler executable, one per target architecture
#     esbuild-linux-x64
#
# Every input comes from the sealed supply and is checked against its manifest
# first. The script refuses rather than assemble a context it cannot vouch for,
# and it never reaches the network. Re-running it against the same destination
# is safe: the destination is rebuilt from scratch each time.
#
# The bundler executable and the precompiled native artifact are
# architecture-specific, so the context is built for one target architecture:
# arm64 or amd64. Each comes from the sealed supply that carries it.
#
# Usage: scripts/build-release-context.sh <destination> <arch> [supply-root]

set -euo pipefail

readonly DEFAULT_SUPPLY_ROOT="/Users/sean/Documents/regent/archive/release-supply"
readonly BASE_SUPPLY="regent-ece.2-20260812"
readonly ARM64_ESBUILD_SUPPLY="regent-ece.2-esbuild-linux-arm64-0.25.4-20260812"
readonly AMD64_ESBUILD_SUPPLY="regent-49a-amd64-slim-20260812"
readonly AMD64_NATIVE_SUPPLY="regent-49a-mdex-native-x86-64-0.2.5-20260812"
readonly MIX_SUPPLY="regent-ece.2-mix-hex-rebar-20260812"

usage() {
  printf 'usage: %s <destination> <arch> [supply-root]\n' "${0##*/}" >&2
  printf '       arch is arm64 or amd64\n' >&2
  exit 2
}

die() {
  printf 'refusing: %s\n' "$1" >&2
  exit 1
}

[ $# -ge 2 ] && [ $# -le 3 ] || usage

destination="$1"
arch="$2"
supply_root="${3:-$DEFAULT_SUPPLY_ROOT}"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
siblings="$(cd -- "$repo_root/.." && pwd)"
privy_source="$siblings/elixir-utils/privy"
regent_ui_source="$siblings/design-system/regent_ui"

# The arm64 native artifact is part of the base supply; the amd64 one arrived
# in its own sealed directory. Both declare it under the same manifest keys.
case "$arch" in
  arm64)
    esbuild_supply_dir="$ARM64_ESBUILD_SUPPLY"
    esbuild_binary="esbuild-linux-arm64"
    native_supply_dir="$BASE_SUPPLY"
    native_manifest_name="SUPPLY-MANIFEST.txt"
    ;;
  amd64)
    esbuild_supply_dir="$AMD64_ESBUILD_SUPPLY"
    esbuild_binary="esbuild-linux-x64"
    native_supply_dir="$AMD64_NATIVE_SUPPLY"
    native_manifest_name="SUPPLY-ADDENDUM.txt"
    ;;
  *) usage ;;
esac

base_supply="$supply_root/$BASE_SUPPLY"
esbuild_supply="$supply_root/$esbuild_supply_dir"
native_supply="$supply_root/$native_supply_dir"
mix_supply="$supply_root/$MIX_SUPPLY"
manifest="$base_supply/SUPPLY-MANIFEST.txt"
mix_addendum="$mix_supply/SUPPLY-ADDENDUM.txt"
esbuild_addendum="$esbuild_supply/SUPPLY-ADDENDUM.txt"
native_manifest="$native_supply/$native_manifest_name"

for required in "$manifest" "$mix_addendum" "$esbuild_addendum" "$native_manifest" \
  "$privy_source" "$regent_ui_source"; do
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

expect_sha256 "$esbuild_binary" \
  "$esbuild_supply/$esbuild_binary" \
  "$(manifest_value "$esbuild_addendum" "$esbuild_binary.sha256")"

expect_sha256 "$(manifest_value "$native_manifest" mdex_native_file)" \
  "$native_supply/$(manifest_value "$native_manifest" mdex_native_file)" \
  "$(manifest_value "$native_manifest" mdex_native_sha256)"

printf 'assembling context at %s\n' "$destination"

mkdir -p "$(dirname -- "$destination")"
staging="$(mktemp -d "${destination%/}.staging.XXXXXX")"
trap 'chmod -R u+w "$staging" 2>/dev/null || true; rm -rf -- "$staging"' EXIT

mkdir -p "$staging/ash-platform" "$staging/elixir-utils/privy" \
  "$staging/design-system/regent_ui" "$staging/npm-cache"

# The checkout enters whole. Dockerfile.dockerignore, not this script, decides
# what the build may see, and a proof test holds it to that.
rsync -a --exclude '.git' --exclude '_build/' --exclude 'node_modules/' \
  "$repo_root/" "$staging/ash-platform/"
rsync -a --exclude '.git' "$privy_source/" "$staging/elixir-utils/privy/"
rsync -a --exclude '.git' --exclude '_build/' --exclude 'node_modules/' \
  "$regent_ui_source/" "$staging/design-system/regent_ui/"

# The sealed npm directory is the cache payload itself, so it lands one level
# down: npm resolves its content under <cache>/_cacache.
rsync -a --chmod=u+rwX "$base_supply/npm-cache/" "$staging/npm-cache/_cacache/"
rsync -a --chmod=u+rwX "$native_supply/rustler-precompiled/" "$staging/rustler-precompiled/"

install -m 0755 "$esbuild_supply/$esbuild_binary" "$staging/$esbuild_binary"

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
printf '  docker buildx build --network=none --pull=false --load \\\n'
printf '    --platform linux/%s --build-arg ESBUILD_TARGET=%s \\\n' \
  "$arch" "${esbuild_binary#esbuild-}"
printf '    -f %s/Dockerfile -t <tag> %s\n' "$destination" "$destination"
