#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

submodule_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-submodules.XXXXXX")
submodule_status_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-submodule-status.XXXXXX")
test_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-test.XXXXXX")
trap 'rm -f "$submodule_log" "$submodule_status_log" "$test_log"' 0 1 2 15

submodules_complete() {
    if ! git submodule status --recursive >"$submodule_status_log" 2>&1; then
        cat "$submodule_status_log"
        return 1
    fi

    cat "$submodule_status_log"
    if [ ! -s "$submodule_status_log" ] || grep -E '^[-+U]' "$submodule_status_log" >/dev/null; then
        echo "Submodule tree is incomplete or not pinned." >&2
        return 1
    fi
}

network_unavailable() {
    grep -E -i \
        'could not resolve (host|proxy)|failed to connect to|connection (timed out|reset by peer)|network is unreachable|could not connect to server|curl: \((6|7|28)\)' \
        "$submodule_log" >/dev/null
}

submodule_update_status=0
git submodule update --init --recursive >"$submodule_log" 2>&1 || submodule_update_status=$?
cat "$submodule_log"

if [ "$submodule_update_status" -ne 0 ]; then
    if ! network_unavailable || ! submodules_complete; then
        exit "$submodule_update_status"
    fi

    echo "Submodule fetch unavailable; using FOUNDRY_OFFLINE=true with complete pinned tree."
    export FOUNDRY_OFFLINE=true
else
    submodules_complete || exit 1
fi

forge build

forge_test_status=0
forge test >"$test_log" 2>&1 || forge_test_status=$?
cat "$test_log"

test_summary=$(grep -E '[0-9]+ tests passed|[0-9]+ tests, [0-9]+ failures|[0-9]+ tests, [0-9]+ failed' "$test_log" | tail -n 1)
if [ -n "$test_summary" ]; then
    printf '%s\n' "$test_summary"
else
    echo "forge test produced no summary/count line." >&2
fi

[ "$forge_test_status" -eq 0 ] || exit "$forge_test_status"
[ -n "$test_summary" ] || exit 1

forge fmt --check
