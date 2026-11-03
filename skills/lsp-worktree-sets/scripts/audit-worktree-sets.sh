#!/usr/bin/env bash
# Report which worktree sets in ~/lsp can be removed with
# remove-worktree-set.sh. Read-only apart from `git fetch --prune`: removes
# nothing, only prints a report and the remove commands for the sets that
# qualify.
#
# Usage:
#   audit-worktree-sets.sh [--no-fetch] [--no-pr]
#
# Covers both layouts: ~/lsp/wt/<set>/<repo> and ~/lsp/<repo>-<set> (sets
# created before 2026-10-21). Worktrees are grouped by set directory name,
# not by branch: an old-layout directory may hold another branch than its
# name says, and that name is what remove-worktree-set.sh takes.
#
# A worktree counts as done when it has no uncommitted or untracked files,
# no stash entry made on its branch, and its HEAD is in the repo's default
# branch (origin/dev if the repo has one, otherwise origin/main) by one of:
#   ancestor  HEAD is reachable from the default branch (merge commit,
#             fast-forward, or a pin that never moved off dev)
#   in-tree   merging HEAD into the default branch changes nothing
#             (squash or rebase merge)
#   pr        every non-merge commit of HEAD is in the default branch or in
#             the head of a merged PR of the branch (squash merge whose
#             lines the default branch has edited since, so in-tree
#             conflicts; the local branch may lag the PR or have merged dev)
#   cherry    every commit ahead has a patch-equivalent commit in the
#             default branch (cherry-picked, e.g. from a release branch)
# A set is removable when every worktree in it is done.
#
# --no-fetch skips refreshing origin/* and fetching PR heads (results are
# then only as fresh as the last fetch); --no-pr skips the GitHub PR lookup
# via gh.

set -uo pipefail

fetch=true
lookup_prs=true

while [ $# -gt 0 ]; do
    case "$1" in
        --no-fetch)
            fetch=false
            shift
            ;;
        --no-pr)
            lookup_prs=false
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

base_dir="$HOME/lsp"
script_dir="$(dirname "$(readlink -f "$0")")"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
rows="$tmp_dir/rows.tsv"
others="$tmp_dir/others.txt"
: > "$rows"
: > "$others"

# Canonical checkouts are the directories with a .git directory (a
# worktree has a .git file instead); only those with worktrees matter.
for src in "$base_dir"/*/; do
    src="${src%/}"
    repo="$(basename "$src")"
    [ -d "$src/.git" ] || continue
    [ "$(git -C "$src" worktree list --porcelain | grep -c '^worktree ')" -gt 1 ] || continue

    if [ "$fetch" = true ]; then
        git -C "$src" fetch --quiet --prune origin || echo "$repo: fetch failed, using local remote refs" >&2
    fi
    if git -C "$src" show-ref --verify --quiet "refs/remotes/origin/dev"; then
        default_ref="origin/dev"
    else
        default_ref="origin/main"
    fi
    default_tree="$(git -C "$src" rev-parse "$default_ref^{tree}")"

    # headRefName <TAB> number <TAB> state <TAB> headRefOid, for every PR.
    prs="$tmp_dir/prs-$repo.tsv"
    : > "$prs"
    if [ "$lookup_prs" = true ]; then
        slug="$(git -C "$src" remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##')"
        gh pr list -R "$slug" --state all --limit 2000 \
            --json headRefName,number,state,headRefOid \
            --jq '.[] | [.headRefName, .number, .state, .headRefOid] | @tsv' > "$prs" \
            || echo "$repo: PR lookup failed, judging by git only" >&2
    fi

    stashes="$(git -C "$src" stash list --format='%gs')"

    # One record per worktree: path, HEAD, branch (empty when detached),
    # prunable flag. The first record is the canonical checkout itself.
    # "|" rather than a tab, since read merges consecutive tabs and so
    # drops empty fields.
    while IFS='|' read -r path head branch prunable; do
        [ "$path" = "$src" ] && continue

        if [ -n "$prunable" ]; then
            echo "$repo: $path is prunable (directory gone) -- git -C $src worktree prune" >> "$others"
            continue
        fi
        case "$path" in
            "$base_dir/wt/"*/"$repo")
                set_name="${path#"$base_dir/wt/"}"
                set_name="${set_name%/"$repo"}"
                layout="wt"
                ;;
            "$base_dir/$repo-"*)
                set_name="${path#"$base_dir/$repo-"}"
                layout="old"
                ;;
            *)
                echo "$repo: $path is outside both layouts (branch ${branch:-detached at ${head:0:8}})" >> "$others"
                continue
                ;;
        esac

        dirty_paths="$(git -C "$path" status --porcelain | cut -c4-)"
        dirty=0
        [ -n "$dirty_paths" ] && dirty="$(wc -l <<< "$dirty_paths")"
        dirty_shown="$(head -3 <<< "$dirty_paths" | paste -sd ',' | sed 's/,/, /g')"
        [ "$dirty" -gt 3 ] && dirty_shown="$dirty_shown (+$((dirty - 3)) more)"

        stash_count=0
        if [ -n "$branch" ] && [ -n "$stashes" ]; then
            stash_count="$(grep -cE "^(WIP on|On) $branch: " <<< "$stashes")"
        fi

        pr_list=""
        merged_heads=()
        if [ -n "$branch" ]; then
            while IFS=$'\t' read -r _ number state oid; do
                pr_list="$pr_list #$number ${state,,}"
                [ "$state" = "MERGED" ] && merged_heads+=("$number:$oid")
            done < <(awk -F'\t' -v b="$branch" '$1 == b' "$prs")
        fi
        pr_list="${pr_list# }"

        ahead="$(git -C "$src" rev-list --count "$default_ref..$head")"
        merge_state=""
        if [ "$ahead" -eq 0 ]; then
            merge_state="ancestor"
        elif merged_tree="$(git -C "$src" merge-tree --write-tree "$default_ref" "$head" 2>/dev/null)" \
            && [ "$(head -1 <<< "$merged_tree")" = "$default_tree" ]; then
            merge_state="in-tree"
        else
            for merged_head in "${merged_heads[@]}"; do
                number="${merged_head%%:*}"
                oid="${merged_head#*:}"
                # A squash-merged PR's head is no longer on any branch.
                if ! git -C "$src" cat-file -e "$oid^{commit}" 2>/dev/null && [ "$fetch" = true ]; then
                    git -C "$src" fetch --quiet origin "refs/pull/$number/head" 2>/dev/null
                fi
                git -C "$src" cat-file -e "$oid^{commit}" 2>/dev/null || continue
                if [ "$(git -C "$src" rev-list --no-merges --count "$head" --not "$default_ref" "$oid")" -eq 0 ]; then
                    merge_state="pr #$number"
                    break
                fi
            done
        fi
        if [ -z "$merge_state" ]; then
            if ! git -C "$src" cherry "$default_ref" "$head" | grep -q '^+'; then
                merge_state="cherry"
            else
                not_on_origin="$(git -C "$src" rev-list --count "$head" --not --remotes=origin)"
                merge_state="NOT IN ${default_ref#origin/}: $ahead ahead"
                [ "$not_on_origin" -gt 0 ] && merge_state="$merge_state, $not_on_origin not on origin"
            fi
        fi

        done_flag=yes
        case "$merge_state" in NOT*) done_flag=no ;; esac
        [ "$dirty" -gt 0 ] && done_flag=no
        [ "$stash_count" -gt 0 ] && done_flag=no

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$set_name" "$layout" "$repo" "${branch:-(detached ${head:0:8})}" \
            "$merge_state" "$dirty" "$stash_count" "${pr_list:--}" "$done_flag" \
            "${dirty_shown:--}" >> "$rows"
    done < <(git -C "$src" worktree list --porcelain | awk '
        /^worktree / { if (path != "") print path "|" head "|" branch "|" prunable
                       path = substr($0, 10); head = ""; branch = ""; prunable = "" }
        /^HEAD /     { head = $2 }
        /^branch /   { branch = substr($2, 12) }
        /^prunable/  { prunable = "yes" }
        END          { if (path != "") print path "|" head "|" branch "|" prunable }')
done

sort -t $'\t' -k1,1 -k3,3 -o "$rows" "$rows"

print_set() {
    local set_name="$1"
    local layout workspace
    layout="$(awk -F'\t' -v s="$set_name" '$1 == s { print $2; exit }' "$rows")"
    workspace="$base_dir/lsp-$set_name.code-workspace"
    printf '%s  [%s layout%s]\n' "$set_name" "$layout" \
        "$([ -f "$workspace" ] || echo ', no workspace file')"
    awk -F'\t' -v s="$set_name" '$1 == s {
        notes = ""
        if ($6 > 0) notes = notes ", " $6 " uncommitted/untracked"
        if ($7 > 0) notes = notes ", " $7 " stash"
        printf "    %-3s %-15s %-40s %s%s  PRs: %s\n", ($9 == "yes" ? "ok" : "!!"), $3, $5, $4, notes, $8
        if ($6 > 0) printf "        dirty: %s\n", $10
    }' "$rows"
}

removable_sets=()
keep_sets=()
for set_name in $(cut -f1 "$rows" | uniq); do
    if awk -F'\t' -v s="$set_name" '$1 == s && $9 != "yes" { found = 1 } END { exit !found }' "$rows"; then
        keep_sets+=("$set_name")
    else
        removable_sets+=("$set_name")
    fi
done

echo "Columns: ok/!!, repo, merge state, branch, problems, PRs for that branch"
echo
echo "=== Removable: every worktree clean and in its default branch (${#removable_sets[@]}) ==="
for set_name in "${removable_sets[@]}"; do print_set "$set_name"; done
echo
echo "=== Keep: at least one worktree (!!) is not done (${#keep_sets[@]}) ==="
for set_name in "${keep_sets[@]}"; do print_set "$set_name"; done

# Leftovers that hold no worktree at all: empty set directories and
# workspace files whose set is gone.
for set_dir in "$base_dir"/wt/*/; do
    set_dir="${set_dir%/}"
    set_name="$(basename "$set_dir")"
    grep -q "^$set_name"$'\t' "$rows" || echo "set directory without worktrees: $set_dir" >> "$others"
done
for workspace in "$base_dir"/lsp-*.code-workspace; do
    set_name="$(basename "$workspace" .code-workspace)"
    set_name="${set_name#lsp-}"
    grep -q "^$set_name"$'\t' "$rows" || echo "workspace file without worktrees: $workspace" >> "$others"
done

echo
echo "=== Other leftovers ==="
if [ -s "$others" ]; then cat "$others"; else echo "none"; fi

echo
echo "=== Remove commands for the removable sets ==="
for set_name in "${removable_sets[@]}"; do
    echo "$script_dir/remove-worktree-set.sh $set_name"
done
