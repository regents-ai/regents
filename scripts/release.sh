#!/usr/bin/env bash
# Builds the committed tree into the release image and proves the image runs.
# Run it through `make release`, which runs every gate on that same tree first.
#
# The build context is `git archive` of HEAD, so nothing uncommitted, ignored
# or outside this repository enters the image; platform/Dockerfile.dockerignore
# admits only the platform, identity, payments, agents and blog sources the
# image is built from.
# The build reuses no cached layers, and the Dockerfile fetches every
# dependency at the version the lockfiles pin; the shared libraries'
# repositories are public, so the build takes no credentials.
#
# The smoke check starts the image against a throwaway PostgreSQL 17 on its own
# Docker network and removes both afterwards. It runs the staging release
# commands against it, starts the server, and checks the health endpoint, the
# home page, a built stylesheet and the running server's database connection.
# It runs as staging because that role admits only the staging database
# hostnames, which the throwaway database answers to on its network.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

commit="$(git rev-parse HEAD)"
image="regents:${commit:0:12}"
run="regents-smoke-$$"
database_url="postgres://smoke:smoke@regents-staging-db.internal/regents_smoke"

cleanup() {
  status=$?
  if [[ $status -ne 0 ]] && docker container inspect "$run-app" >/dev/null 2>&1; then
    echo "Server log:" >&2
    docker logs --tail 40 "$run-app" >&2
  fi
  docker rm --force "$run-app" "$run-db" >/dev/null 2>&1 || true
  docker network rm "$run" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Retries a command once a second for up to a minute.
wait_for() {
  local what="$1"
  shift
  for _ in $(seq 60); do
    if "$@" >/dev/null 2>&1; then return; fi
    sleep 1
  done
  echo "Smoke check failed: $what did not answer within a minute." >&2
  exit 1
}

fail() {
  echo "Smoke check failed: $1" >&2
  exit 1
}

echo "==> Building $image from commit $commit"
git archive --format=tar "$commit" |
  docker build --no-cache --file platform/Dockerfile \
    --label "org.opencontainers.image.revision=$commit" --tag "$image" -
digest="$(docker image inspect --format '{{.Id}}' "$image")"

echo "==> Starting a throwaway database"
docker network create --ipv6 "$run" >/dev/null
docker run --detach --name "$run-db" --network "$run" \
  --network-alias regents-staging-db.internal \
  --env POSTGRES_USER=smoke --env POSTGRES_DB=regents_smoke \
  --env POSTGRES_HOST_AUTH_METHOD=trust \
  docker.io/library/postgres:17 >/dev/null
wait_for "the database" docker exec "$run-db" pg_isready --quiet --host 127.0.0.1 --username smoke

# Production requires a Base read endpoint; the public one is enough to boot.
release_env=(
  --network "$run"
  --env REGENTS_DEPLOYMENT_ROLE=staging
  --env REGENTS_APP_SURFACES=on
  --env BASE_READ_RPC_URL=https://mainnet.base.org
)

echo "==> Creating and migrating the database with the release commands"
docker run --rm "${release_env[@]}" --env DATABASE_DIRECT_URL="$database_url" "$image" /app/bin/bootstrap-staging
docker run --rm "${release_env[@]}" --env DATABASE_DIRECT_URL="$database_url" "$image" /app/bin/migrate
pending="$(docker run --rm "${release_env[@]}" --env DATABASE_DIRECT_URL="$database_url" "$image" /app/bin/pending-migrations | tail -n 1)"
[[ $pending == none ]] || fail "the database and the release disagree: $pending"

echo "==> Starting the server"
docker run --detach --name "$run-app" "${release_env[@]}" \
  --publish 127.0.0.1::4000 \
  --env DATABASE_POOLED_URL="$database_url" \
  --env PHX_HOST=localhost \
  --env SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  "$image" >/dev/null
base="http://$(docker port "$run-app" 4000/tcp | head -n 1)"
wait_for "the health endpoint" curl --silent --fail "$base/healthz"

health="$(curl --silent --fail "$base/healthz")"
[[ $health == ok ]] || fail "the health endpoint answered \"$health\""

home="$(curl --silent --fail "$base/")"
stylesheet="$(grep -oE '/assets/[^"]+-[0-9a-f]{32}\.css' <<<"$home" | head -n 1)" ||
  fail "the home page links no fingerprinted stylesheet"
stylesheet_answer="$(curl --silent --fail --output /dev/null --write-out '%{http_code} %{content_type} %{size_download} bytes' "$base$stylesheet")"
[[ $stylesheet_answer == "200 text/css"* ]] || fail "$stylesheet answered $stylesheet_answer"

connected_database="$(docker exec "$run-app" /app/bin/regents rpc \
  '[[name]] = Regents.Repo.query!("SELECT current_database()").rows; IO.puts(name)')"
[[ $connected_database == regents_smoke ]] || fail "the server's database answered \"$connected_database\""

echo
echo "Release built and smoke-checked"
echo "  app commit      $commit"
git show "$commit:platform/mix.lock" | grep -oE '\{:git, "[^"]+", "[0-9a-f]{40}"' | sort -u |
  sed -E 's/\{:git, "([^"]+)", "([0-9a-f]+)"/  shared library  \1 \2/'
echo "  image           $image"
echo "  image digest    $digest"
echo "  migrations      bootstrap-staging and migrate succeeded; pending-migrations: $pending"
echo "  health          $base/healthz answered $health"
echo "  static asset    $stylesheet answered $stylesheet_answer"
echo "  database        the running server queried $connected_database"
