#!/usr/bin/env bash
# Deploys the committed HEAD to regents.sh. It refuses a commit that is not on
# origin/main. Fly builds `git archive` of the commit, so nothing uncommitted
# enters the image, labels the image with the commit it was built from and
# passes it in as SOURCE_COMMIT. The one machine then takes that image, with no
# spare machines added.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

app="regents-sh-web"
commit="$(git rev-parse HEAD)"

git fetch --quiet origin main
if ! git merge-base --is-ancestor "$commit" origin/main; then
  echo "Refusing to deploy: ${commit:0:7} is not on origin/main. Push it to main first." >&2
  exit 1
fi

tag="main-${commit:0:12}"
context="$(mktemp -d)"
trap 'rm -r "$context"' EXIT

git archive --format=tar "$commit" | tar -x -C "$context"

echo "==> Building registry.fly.io/$app:$tag from commit $commit"
(cd "$context" && fly deploy . --app "$app" --config platform/fly.toml \
  --build-only --push --remote-only --image-label "$tag" \
  --ignorefile platform/Dockerfile.dockerignore \
  --build-arg SOURCE_COMMIT="$commit" \
  --label "org.opencontainers.image.revision=$commit")

echo "==> Deploying registry.fly.io/$app:$tag"
fly deploy --app "$app" --config platform/fly.toml \
  --image "registry.fly.io/$app:$tag" --ha=false
