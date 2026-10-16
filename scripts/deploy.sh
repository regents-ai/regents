#!/usr/bin/env bash
# Deploys the committed HEAD to regents.sh. Fly builds `git archive` of the
# commit, so nothing uncommitted enters the image, and labels the image with the
# commit it was built from. The one machine then takes that image, with no
# spare machines added.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

app="regents-sh-web"
commit="$(git rev-parse HEAD)"
tag="main-${commit:0:12}"
context="$(mktemp -d)"
trap 'rm -r "$context"' EXIT

git archive --format=tar "$commit" | tar -x -C "$context"

echo "==> Building registry.fly.io/$app:$tag from commit $commit"
(cd "$context" && fly deploy . --app "$app" --config platform/fly.toml \
  --build-only --push --remote-only --image-label "$tag" \
  --label "org.opencontainers.image.revision=$commit")

echo "==> Deploying registry.fly.io/$app:$tag"
fly deploy --app "$app" --config platform/fly.toml \
  --image "registry.fly.io/$app:$tag" --ha=false
