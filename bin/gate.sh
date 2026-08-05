#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

# Committed required-set manifest. The root entries are the direct submodules
# targeted by foundry.toml's remappings. The nested entries are the two
# v4-periphery submodules imported by its source. The checks below keep this
# manifest tied to those declarations instead of allowing a remembered list.
required_submodule_paths='
lib/forge-std
lib/v4-core
lib/v4-periphery
lib/permit2
lib/solmate
lib/solady
lib/openzeppelin-contracts
lib/uerc20-factory
lib/v4-periphery/lib/permit2
lib/v4-periphery/lib/v4-core
'

root_required_submodule_paths() {
    for path in $required_submodule_paths; do
        case "$path" in
            lib/*/lib/*)
                ;;
            *)
                printf '%s\n' "$path"
                ;;
        esac
    done
}

nested_required_submodule_paths() {
    for path in $required_submodule_paths; do
        case "$path" in
            lib/*/lib/*)
                printf '%s\n' "$path"
                ;;
        esac
    done
}

foundry_remappings() {
    if [ -f remappings.txt ]; then
        awk -F= \
            '/^[[:space:]]*[^#[:space:]]+\/=/{gsub(/[[:space:]]/, "", $1); gsub(/[[:space:]]/, "", $2); print $1 "=" $2}' \
            remappings.txt
    fi

    if [ -f foundry.toml ]; then
        awk -F'"' '/^[[:space:]]*"[^"]+\/=/{print $2}' foundry.toml
    fi
}

has_path() {
    list=$1
    needle=$2
    printf '%s\n' "$list" | grep -F -x "$needle" >/dev/null
}

check_root_manifest() {
    remapping_manifest=$(foundry_remappings | sort -u)
    if [ -z "$remapping_manifest" ]; then
        echo "No Foundry remappings were found; refusing to guess the required submodule set." >&2
        return 1
    fi

    if [ ! -f .gitmodules ]; then
        echo "Missing .gitmodules; refusing to guess the required submodule set." >&2
        return 1
    fi

    root_gitmodule_paths=$(git config --file .gitmodules --get-regexp '\.path$' | awk '{print $2}')
    root_manifest=$(root_required_submodule_paths)

    if [ -z "$root_gitmodule_paths" ] || [ -z "$root_manifest" ]; then
        echo "Empty root submodule manifest; refusing to continue." >&2
        return 1
    fi

    for path in $root_gitmodule_paths; do
        case "$path" in
            lib/*/lib/*)
                echo "Root .gitmodules unexpectedly contains a nested path: $path" >&2
                return 1
                ;;
        esac

        if ! has_path "$root_manifest" "$path"; then
            echo "Required-set manifest is missing root submodule declared by .gitmodules: $path" >&2
            return 1
        fi
    done

    for path in $root_manifest; do
        if ! has_path "$root_gitmodule_paths" "$path"; then
            echo "Required-set manifest contains undeclared root submodule: $path" >&2
            return 1
        fi

        remapping_found=0
        for mapping in $remapping_manifest; do
            mapping_target=${mapping#*=}
            mapping_target=${mapping_target%/}
            case "$mapping_target/" in
                "$path/"*)
                    remapping_found=1
                    ;;
            esac
        done

        if [ "$remapping_found" -ne 1 ]; then
            echo "Required root submodule is not targeted by a Foundry remapping: $path" >&2
            return 1
        fi
    done

    for mapping in $remapping_manifest; do
        mapping_target=${mapping#*=}
        mapping_target=${mapping_target%/}
        case "$mapping_target" in
            lib/*)
                remapping_found=0
                for path in $root_manifest; do
                    case "$mapping_target/" in
                        "$path/"*)
                            remapping_found=1
                            ;;
                    esac
                done

                if [ "$remapping_found" -ne 1 ]; then
                    echo "Foundry remapping targets an unlisted submodule path: $mapping" >&2
                    return 1
                fi
                ;;
        esac
    done

    echo "Required root submodule set checked against .gitmodules and Foundry remappings."
}

check_nested_manifest() {
    nested_manifest=$(nested_required_submodule_paths)
    if [ -z "$nested_manifest" ]; then
        echo "Empty nested submodule manifest; refusing to continue." >&2
        return 1
    fi

    for path in $nested_manifest; do
        parent=${path%/lib/*}
        child=${path#"$parent/"}

        if [ ! -f "$parent/.gitmodules" ]; then
            echo "Nested manifest parent is unavailable: $parent/.gitmodules" >&2
            return 1
        fi

        nested_gitmodule_paths=$(git -C "$parent" config --file .gitmodules --get-regexp '\.path$' | awk '{print $2}')
        if ! has_path "$nested_gitmodule_paths" "$child"; then
            echo "Nested manifest path is not declared by $parent/.gitmodules: $path" >&2
            return 1
        fi

        nested_prefix=
        for mapping in $remapping_manifest; do
            mapping_prefix=${mapping%%=*}
            mapping_target=${mapping#*=}
            mapping_target=${mapping_target%/}
            case "$mapping_target/" in
                "$child/"*)
                    nested_prefix=$mapping_prefix
                    ;;
            esac
        done

        if [ -z "$nested_prefix" ]; then
            echo "Nested manifest path has no matching Foundry remapping: $path" >&2
            return 1
        fi

        if ! grep -R -F -e "\"$nested_prefix" -e "'$nested_prefix" "$parent/src" >/dev/null 2>&1; then
            echo "Nested manifest path is not imported by $parent/src: $path" >&2
            return 1
        fi
    done

    echo "Required nested submodule set checked against v4-periphery declarations, imports, and remappings."
}

submodule_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-submodules.XXXXXX")
submodule_status_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-submodule-status.XXXXXX")
test_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-test.XXXXXX")
trap 'rm -f "$submodule_log" "$submodule_status_log" "$test_log"' 0 1 2 15

submodule_status_for_path() {
    path=$1
    case "$path" in
        lib/*/lib/*)
            parent=${path%/lib/*}
            child=${path#"$parent/"}
            git -C "$parent" submodule status -- "$child"
            ;;
        *)
            git submodule status -- "$path"
            ;;
    esac
}

submodules_complete_for_paths() {
    paths=$1
    complete=0
    : >"$submodule_status_log"

    for path in $paths; do
        module_status=$(submodule_status_for_path "$path" 2>&1) || {
            printf '%s: %s\n' "$path" "$module_status" >>"$submodule_status_log"
            complete=1
            continue
        }

        if [ -z "$module_status" ]; then
            printf '%s: no submodule status\n' "$path" >>"$submodule_status_log"
            complete=1
            continue
        fi

        printf '%s: %s\n' "$path" "$module_status" >>"$submodule_status_log"
        status_prefix=$(printf '%s' "$module_status" | cut -c1)
        if [ "$status_prefix" != " " ]; then
            complete=1
        fi
    done

    cat "$submodule_status_log"
    if [ "$complete" -ne 0 ]; then
        echo "Required submodule set is incomplete or not pinned." >&2
        return 1
    fi
}

submodules_complete() {
    submodules_complete_for_paths "$required_submodule_paths"
}

root_submodules_complete() {
    submodules_complete_for_paths "$(root_required_submodule_paths)"
}

network_unavailable() {
    grep -E -i \
        'could not resolve (host|proxy)|failed to connect to|connection (timed out|reset by peer)|network is unreachable|could not connect to server|curl: \((6|7|28)\)' \
        "$submodule_log" >/dev/null
}

check_root_manifest || exit 1

submodule_update_status=0
root_fetch_unavailable=0
for path in $(root_required_submodule_paths); do
    git submodule update --init -- "$path" >>"$submodule_log" 2>&1 || {
        submodule_update_status=$?
        break
    }
done

if [ "$submodule_update_status" -ne 0 ]; then
    if ! network_unavailable || ! root_submodules_complete; then
        cat "$submodule_log"
        exit "$submodule_update_status"
    fi

    root_fetch_unavailable=1
fi

check_nested_manifest || exit 1

submodule_update_status=0
nested_fetch_unavailable=0
for path in $(nested_required_submodule_paths); do
    parent=${path%/lib/*}
    child=${path#"$parent/"}
    git -C "$parent" submodule update --init -- "$child" >>"$submodule_log" 2>&1 || {
        submodule_update_status=$?
        break
    }
done
cat "$submodule_log"

if [ "$submodule_update_status" -ne 0 ]; then
    if ! network_unavailable || ! submodules_complete; then
        exit "$submodule_update_status"
    fi

    nested_fetch_unavailable=1
fi

if [ "$root_fetch_unavailable" -ne 0 ] || [ "$nested_fetch_unavailable" -ne 0 ]; then
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
