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

# The switch to the new image runs the migrations and briefly adds a second
# machine's connections to the production database every site shares, which
# fits two switches at once. It takes whichever of the two places is free, or
# waits for the second.
switch() {
  local place=/tmp/regent-shared-db-release.lock
  lockf -k -s -t 0 "$place" true || place=/tmp/regent-shared-db-release-2.lock
  echo "==> Deploying registry.fly.io/$app:$tag (waits for $place if it is taken)"
  lockf -k "$place" fly deploy --app "$app" --config platform/fly.toml \
    --image "registry.fly.io/$app:$tag" --ha=false
}

release() {
  echo "==> Building registry.fly.io/$app:$tag from commit $commit"
  (cd "$context" && fly deploy . --app "$app" --config platform/fly.toml \
    --build-only --push --remote-only --image-label "$tag" \
    --ignorefile platform/Dockerfile.dockerignore \
    --build-arg SOURCE_COMMIT="$commit" \
    --label "org.opencontainers.image.revision=$commit")
  switch
}

# One regents.sh deploy at a time; other sites' deploys never wait on it.
lock="/tmp/regent-release-$app.lock"
echo "==> Waiting for any other regents.sh deploy holding $lock"
export app commit tag context
export -f release switch
lockf -k "$lock" bash -euo pipefail -c release
