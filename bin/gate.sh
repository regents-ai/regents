#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

root_submodule_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-root-submodules.XXXXXX")
nested_submodule_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-nested-submodules.XXXXXX")
submodule_attempt_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-submodule-attempt.XXXXXX")
phase_paths_snapshot_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-phase-paths.XXXXXX")
submodule_status_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-submodule-status.XXXXXX")
test_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-test.XXXXXX")
required_paths_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-required-paths.XXXXXX")
root_paths_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-root-paths.XXXXXX")
nested_paths_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-nested-paths.XXXXXX")
effective_remappings_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-effective-remappings.XXXXXX")
root_effective_remappings_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-root-effective-remappings.XXXXXX")
gitmodule_paths_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-gitmodule-paths.XXXXXX")
imports_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-imports.XXXXXX")
resolution_paths_log=$(mktemp "${TMPDIR:-/tmp}/regent-gate-resolution-paths.XXXXXX")
trap 'rm -f "$root_submodule_log" "$nested_submodule_log" "$submodule_attempt_log" "$phase_paths_snapshot_log" "$submodule_status_log" "$test_log" "$required_paths_log" "$root_paths_log" "$nested_paths_log" "$effective_remappings_log" "$root_effective_remappings_log" "$gitmodule_paths_log" "$imports_log" "$resolution_paths_log"' 0 1 2 15

: >"$required_paths_log"
: >"$root_paths_log"
: >"$nested_paths_log"
: >"$resolution_paths_log"

has_path() {
    list_file=$1
    wanted_path=$2
    grep -F -x "$wanted_path" "$list_file" >/dev/null 2>&1
}

append_unique_path() {
    destination_file=$1
    path_value=$2

    [ -n "$path_value" ] || return 0
    if ! has_path "$destination_file" "$path_value"; then
        printf '%s\n' "$path_value" >>"$destination_file"
    fi
}

join_project_path() {
    join_project=$1
    join_relative=$2

    if [ "$join_project" = "." ]; then
        printf '%s\n' "$join_relative"
    elif [ -n "$join_relative" ]; then
        printf '%s/%s\n' "$join_project" "$join_relative"
    else
        printf '%s\n' "$join_project"
    fi
}

project_has_gitmodules() {
    gitmodules_project=$1
    [ -f "$gitmodules_project/.gitmodules" ]
}

project_gitmodule_paths() {
    gitmodule_project=$1
    gitmodules_file="$gitmodule_project/.gitmodules"

    [ -f "$gitmodules_file" ] || return 0
    git config --file "$gitmodules_file" --get-regexp '\.path$' 2>/dev/null |
        awk '{print $2}'
}

normalize_remappings() {
    awk -F= '
        function trim(value) {
            gsub(/^[[:space:]]+/, "", value)
            gsub(/[[:space:]]+$/, "", value)
            return value
        }
        {
            if ($0 ~ /^[[:space:]]*#/ || index($0, "=") == 0) {
                next
            }

            prefix = trim($1)
            target = substr($0, index($0, "=") + 1)
            sub(/[[:space:]]*#.*/, "", target)
            target = trim(target)
            gsub(/[[:space:]]/, "", prefix)

            if (prefix ~ /\/$/ && target != "") {
                print prefix "=" target
            }
        }
    '
}

toml_remappings() {
    toml_file=$1

    [ -f "$toml_file" ] || return 0
    awk -F'"' '{
        for (field = 2; field <= NF; field += 2) {
            if ($field ~ /\/=.*\// || $field ~ /\/=.[^[:space:]]*/) {
                print $field
            }
        }
    }' "$toml_file"
    awk -F"'" '{
        for (field = 2; field <= NF; field += 2) {
            if ($field ~ /\/=.*\// || $field ~ /\/=.[^[:space:]]*/) {
                print $field
            }
        }
    }' "$toml_file"
}

project_configured_remappings() {
    remapping_project=$1

    if [ -f "$remapping_project/remappings.txt" ]; then
        normalize_remappings <"$remapping_project/remappings.txt"
    fi
    toml_remappings "$remapping_project/foundry.toml" | normalize_remappings
}

project_effective_remappings() {
    effective_project=$1
    generated_remappings=

    project_configured_remappings "$effective_project"

    if command -v forge >/dev/null 2>&1; then
        if generated_remappings=$(cd "$effective_project" && FOUNDRY_OFFLINE=true forge remappings 2>/dev/null); then
            printf '%s\n' "$generated_remappings" | normalize_remappings
        fi
    fi
}

project_import_paths() {
    import_project=$1
    import_source_dir=

    if [ "$import_project" = "." ]; then
        import_source_dirs='src test script'
    else
        import_source_dirs='src'
    fi

    for import_source_dir in $import_source_dirs; do
        import_source_path="$import_project/$import_source_dir"
        if [ -d "$import_source_path" ]; then
            if [ "$import_project" = "." ]; then
                grep -R -h --include='*.sol' -E '^[[:space:]]*import([[:space:]]|\{)' "$import_source_path" 2>/dev/null
            else
                grep -R -h --exclude-dir=test --include='*.sol' -E '^[[:space:]]*import([[:space:]]|\{)' "$import_source_path" 2>/dev/null
            fi |
                awk -F'"' '{
                    for (field = 2; field <= NF; field += 2) {
                        if ($field != "") {
                            print $field
                            break
                        }
                    }
                }'
        fi
    done | sort -u
}

find_mapping_for_import() {
    import_value=$1
    mappings_file=$2
    best_prefix=
    best_target=

    while IFS= read -r mapping_line; do
        [ -n "$mapping_line" ] || continue
        mapping_prefix=${mapping_line%%=*}
        mapping_target=${mapping_line#*=}

        case "$import_value" in
            "$mapping_prefix"*)
                if [ -z "$best_prefix" ] || [ "${#mapping_prefix}" -gt "${#best_prefix}" ]; then
                    best_prefix=$mapping_prefix
                    best_target=$mapping_target
                fi
                ;;
        esac
    done <"$mappings_file"

    if [ -n "$best_prefix" ]; then
        printf '%s|%s\n' "$best_prefix" "$best_target"
    else
        return 1
    fi
}

resolve_target() {
    resolve_origin_project=$1
    resolve_target_value=$2
    resolve_record_required=$3
    resolve_origin=$4
    current_project=$resolve_origin_project
    remaining_target=$resolve_target_value
    first_root_path=

    while :; do
        case "$remaining_target" in
            ./*)
                remaining_target=${remaining_target#./}
                ;;
            *)
                break
                ;;
        esac
    done

    case "$remaining_target" in
        ""|/*|../*|*/../*|*/..)
            echo "Unsupported remapping target for $resolve_origin: $resolve_origin_project -> $resolve_target_value" >&2
            return 1
            ;;
    esac

    while [ -n "$remaining_target" ]; do
        : >"$gitmodule_paths_log"
        project_gitmodule_paths "$current_project" >"$gitmodule_paths_log"
        best_child=
        best_child_length=0

        while IFS= read -r child_path; do
            [ -n "$child_path" ] || continue
            case "$remaining_target/" in
                "$child_path/"*)
                    if [ -z "$best_child" ] || [ "${#child_path}" -gt "$best_child_length" ]; then
                        best_child=$child_path
                        best_child_length=${#child_path}
                    fi
                    ;;
            esac
        done <"$gitmodule_paths_log"

        if [ -z "$best_child" ]; then
            break
        fi

        current_project=$(join_project_path "$current_project" "$best_child")
        remaining_target=${remaining_target#"$best_child"}
        remaining_target=${remaining_target#/}

        if [ -z "$first_root_path" ] && [ "$resolve_origin_project" = "." ]; then
            first_root_path=$current_project
        fi

        if [ "$resolve_record_required" -eq 1 ]; then
            append_unique_path "$required_paths_log" "$current_project"
            if [ -n "$first_root_path" ]; then
                append_unique_path "$root_paths_log" "$first_root_path"
            fi
        fi
    done

    if [ -n "$remaining_target" ] && project_has_gitmodules "$current_project"; then
        case "$remaining_target" in
            lib/*)
                echo "Unrepresented submodule path for $resolve_origin: $resolve_origin_project -> $resolve_target_value" >&2
                return 1
                ;;
        esac
    fi

    resolved_submodule_path=$current_project
    resolved_path=$(join_project_path "$current_project" "$remaining_target")
}

derive_project() {
    derive_project_path=$1
    derive_root_project=$2

    project_effective_remappings "$derive_project_path" | sort -u >"$effective_remappings_log"
    if [ "$derive_root_project" -eq 1 ]; then
        cp "$effective_remappings_log" "$root_effective_remappings_log"
    fi

    while IFS= read -r mapping_line; do
        [ -n "$mapping_line" ] || continue
        mapping_target=${mapping_line#*=}
        if ! resolve_target "$derive_project_path" "$mapping_target" 0 "remapping $mapping_line in $derive_project_path"; then
            return 1
        fi
    done <"$effective_remappings_log"

    while IFS= read -r mapping_line; do
        [ -n "$mapping_line" ] || continue
        mapping_target=${mapping_line#*=}
        if [ "$derive_root_project" -eq 1 ]; then
            mapping_origin="root remapping $mapping_line"
        else
            mapping_origin="remapping $mapping_line in $derive_project_path"
        fi
        if ! resolve_target "$derive_project_path" "$mapping_target" 1 "$mapping_origin"; then
            return 1
        fi
    done <"$effective_remappings_log"

    project_import_paths "$derive_project_path" >"$imports_log"
    while IFS= read -r import_value; do
        [ -n "$import_value" ] || continue

        case "$import_value" in
            ./*|../*|src/*|test/*|script/*|reference/*)
                continue
                ;;
        esac

        root_fallback=0
        if ! mapping_match=$(find_mapping_for_import "$import_value" "$effective_remappings_log"); then
            if [ "$derive_root_project" -eq 0 ] && mapping_match=$(find_mapping_for_import "$import_value" "$root_effective_remappings_log"); then
                root_fallback=1
            else
                echo "No effective Foundry remapping for import in $derive_project_path: $import_value" >&2
                return 1
            fi
        fi

        mapping_prefix=${mapping_match%%|*}
        mapping_target=${mapping_match#*|}
        mapping_suffix=${import_value#"$mapping_prefix"}
        case "$mapping_target" in
            */)
                ;;
            *)
                mapping_target="$mapping_target/"
                ;;
        esac
        case "$mapping_target" in
            */)
                ;;
            *)
                mapping_target="$mapping_target/"
                ;;
        esac
        if [ "$root_fallback" -eq 1 ]; then
            if ! resolve_target . "$mapping_target$mapping_suffix" 1 "root fallback import $import_value in $derive_project_path"; then
                return 1
            fi
        elif ! resolve_target "$derive_project_path" "$mapping_target$mapping_suffix" 1 "import $import_value in $derive_project_path"; then
            return 1
        fi

        if [ "$root_fallback" -eq 1 ]; then
            root_module_name=${resolved_submodule_path##*/}
            : >"$gitmodule_paths_log"
            project_gitmodule_paths "$derive_project_path" >"$gitmodule_paths_log"
            while IFS= read -r child_path; do
                [ -n "$child_path" ] || continue
                child_name=${child_path##*/}
                if [ "$child_name" = "$root_module_name" ]; then
                    nested_import_path=$(join_project_path "$derive_project_path" "$child_path/$mapping_suffix")
                    append_unique_path "$required_paths_log" "$(join_project_path "$derive_project_path" "$child_path")"
                    if [ -e "$nested_import_path" ]; then
                        resolved_path=$nested_import_path
                    fi
                fi
            done <"$gitmodule_paths_log"
        fi
        if [ ! -e "$resolved_path" ] && [ "$resolved_submodule_path" != "$derive_project_path" ]; then
            fallback_import_path=$(join_project_path "$resolved_submodule_path" "$mapping_suffix")
            if [ -e "$fallback_import_path" ]; then
                resolved_path=$fallback_import_path
            fi
        fi
        append_unique_path "$resolution_paths_log" "$resolved_path"
    done <"$imports_log"
}

check_root_paths() {
    if [ ! -f .gitmodules ]; then
        echo "Missing .gitmodules; refusing to guess the required root submodule set." >&2
        return 1
    fi

    project_gitmodule_paths . | sort -u >"$gitmodule_paths_log"
    if [ ! -s "$gitmodule_paths_log" ] || [ ! -s "$root_paths_log" ]; then
        echo "Could not derive a non-empty root submodule set from Foundry remappings." >&2
        return 1
    fi

    while IFS= read -r declared_path; do
        [ -n "$declared_path" ] || continue
        if ! has_path "$root_paths_log" "$declared_path"; then
            echo "Root .gitmodules path is not represented by a configured Foundry remapping: $declared_path" >&2
            return 1
        fi
    done <"$gitmodule_paths_log"

    while IFS= read -r derived_path; do
        [ -n "$derived_path" ] || continue
        if ! has_path "$gitmodule_paths_log" "$derived_path"; then
            echo "Derived root path is not declared by .gitmodules: $derived_path" >&2
            return 1
        fi
    done <"$root_paths_log"
}

submodules_complete_for_paths() {
    paths_file=$1
    status_command=0

    : >"$submodule_status_log"
    git submodule status --recursive >"$submodule_status_log" 2>&1 || status_command=$?
    cat "$submodule_status_log"
    if [ "$status_command" -ne 0 ]; then
        echo "Unable to inspect the submodule tree." >&2
        return 1
    fi

    while IFS= read -r required_path; do
        [ -n "$required_path" ] || continue
        module_status=$(awk -v wanted="$required_path" '$2 == wanted {print; exit}' "$submodule_status_log")
        if [ -z "$module_status" ]; then
            echo "Required submodule has no status entry: $required_path" >&2
            return 1
        fi

        status_prefix=$(printf '%s' "$module_status" | cut -c1)
        if [ "$status_prefix" != " " ]; then
            echo "Required submodule is incomplete or not pinned: $required_path" >&2
            return 1
        fi
    done <"$paths_file"
}

network_unavailable() {
    attempt_file=$1
    grep -E -i \
        'could not resolve (host|proxy)|failed to connect to|connection (timed out|reset by peer)|network is unreachable|could not connect to server|curl: \((6|7|28)\)' \
        "$attempt_file" >/dev/null 2>&1
}

is_root_path() {
    root_check_path=$1
    has_path "$root_paths_log" "$root_check_path"
}

update_one_submodule() {
    update_path=$1

    if is_root_path "$update_path"; then
        git submodule update --init -- "$update_path"
    else
        update_parent=${update_path%/lib/*}
        update_child=${update_path#"$update_parent/"}
        if [ "$update_parent" = "$update_path" ] || [ ! -d "$update_parent" ]; then
            echo "Cannot locate initialized parent for required submodule: $update_path" >&2
            return 1
        fi
        git -C "$update_parent" submodule update --init -- "$update_child"
    fi
}

update_submodule_phase() {
    phase_log=$1
    phase_paths=$2
    phase_fetch_unavailable=0
    phase_status=0

    : >"$phase_log"
    cp "$phase_paths" "$phase_paths_snapshot_log"
    # shellcheck disable=SC2094
    while IFS= read -r update_path; do
        [ -n "$update_path" ] || continue
        : >"$submodule_attempt_log"
        if update_one_submodule "$update_path" >"$submodule_attempt_log" 2>&1; then
            cat "$submodule_attempt_log" >>"$phase_log"
        else
            phase_status=$?
            cat "$submodule_attempt_log" >>"$phase_log"
            cat "$phase_log"
            if ! network_unavailable "$submodule_attempt_log" || ! submodules_complete_for_paths "$phase_paths_snapshot_log"; then
                return "$phase_status"
            fi
            phase_fetch_unavailable=1
            break
        fi
    done <"$phase_paths_snapshot_log"

    cat "$phase_log"
    return 0
}

build_nested_paths() {
    : >"$nested_paths_log"
    while IFS= read -r required_path; do
        [ -n "$required_path" ] || continue
        if ! is_root_path "$required_path"; then
            printf '%s\n' "$required_path" >>"$nested_paths_log"
        fi
    done <"$required_paths_log"
}

check_resolved_paths() {
    while IFS= read -r resolved_import_path; do
        [ -n "$resolved_import_path" ] || continue
        if [ ! -e "$resolved_import_path" ]; then
            echo "Remapping/import path is not present after required submodule initialization: $resolved_import_path" >&2
            return 1
        fi
    done <"$resolution_paths_log"
}

derive_project . 1
check_root_paths

root_fetch_unavailable=0
nested_fetch_unavailable=0

if update_submodule_phase "$root_submodule_log" "$root_paths_log"; then
    if [ "$phase_fetch_unavailable" -ne 0 ]; then
        root_fetch_unavailable=1
    fi
else
    phase_status=$?
    exit "$phase_status"
fi

submodules_complete_for_paths "$root_paths_log"

previous_required_count=0
while :; do
    derive_project . 1
    check_root_paths

    cp "$required_paths_log" "$phase_paths_snapshot_log"
    while IFS= read -r required_project; do
        [ -n "$required_project" ] || continue
        derive_project "$required_project" 0
    done <"$phase_paths_snapshot_log"

    build_nested_paths
    if [ -s "$nested_paths_log" ]; then
        if [ "$nested_fetch_unavailable" -eq 0 ]; then
            if update_submodule_phase "$nested_submodule_log" "$nested_paths_log"; then
                if [ "$phase_fetch_unavailable" -ne 0 ]; then
                    nested_fetch_unavailable=1
                fi
            else
                phase_status=$?
                exit "$phase_status"
            fi
        elif ! submodules_complete_for_paths "$nested_paths_log"; then
            exit 1
        fi
    fi

    current_required_count=$(wc -l <"$required_paths_log" | tr -d ' ')
    if [ "$current_required_count" -eq "$previous_required_count" ]; then
        break
    fi
    previous_required_count=$current_required_count
done

if [ "$root_fetch_unavailable" -ne 0 ] || [ "$nested_fetch_unavailable" -ne 0 ]; then
    echo "Submodule fetch unavailable; using FOUNDRY_OFFLINE=true with complete pinned tree."
    export FOUNDRY_OFFLINE=true
fi

check_resolved_paths
submodules_complete_for_paths "$required_paths_log"

echo "Derived and completeness-verified required submodule paths:"
sort -u "$required_paths_log"

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
