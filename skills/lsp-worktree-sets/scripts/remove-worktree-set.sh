#!/usr/bin/env bash
# Remove a worktree set created by new-worktree-set.sh: the worktree
# directory (venv and all) in each repo, the set directory with its symlinks
# to the canonical checkouts, and the generated workspace file.
# Branches are left alone unless --delete-branch is passed.
#
# Handles both layouts: ~/lsp/wt/<branch>/<repo> (current) and
# ~/lsp/<repo>-<branch> (sets created before 2026-10-21).
#
# Usage:
#   remove-worktree-set.sh <branch-name> [--repos repo1,repo2,...] [--no-deps] [--force] [--delete-branch]
#
# - Only removes a repo's worktree if it actually exists;
#   safe to run with the full default repo list even if only some were used.
#   Without --repos, worktrees of non-default repos found in the wt/ set
#   directory (e.g. gen-epix-R) are removed too.
# - `git worktree remove` refuses on uncommitted changes by default -- that
#   safety net is intentional; pass --force to override it (discards them).
# - --delete-branch does a *safe* `git branch -d` (fails loudly if unmerged)
#   after the worktree is removed, for every repo whose worktree existed.
#   Never force-deletes a branch; if you want that, do it yourself.

set -uo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <branch-name> [--repos repo1,repo2,...] [--no-deps] [--force] [--delete-branch]" >&2
    exit 1
fi

branch_name="$1"
shift

default_repos="gen-epix-api idsdb lsp-data lsp-api lsp-kubernetes"
repos="$default_repos"
repos_given=false
add_deps=true
force=false
delete_branch=false

while [ $# -gt 0 ]; do
    case "$1" in
        --repos)
            repos="$(echo "$2" | tr ',' ' ')"
            repos_given=true
            shift 2
            ;;
        --no-deps)
            add_deps=false
            shift
            ;;
        --force)
            force=true
            shift
            ;;
        --delete-branch)
            delete_branch=true
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

declare -A editable_deps=(
    [lsp-data]="gen-epix-api"
    [idsdb]="gen-epix-api"
    [gen-epix-R]="gen-epix-api"
)

if [ "$add_deps" = true ]; then
    for repo in $repos; do
        dep="${editable_deps[$repo]:-}"
        if [ -n "$dep" ] && [[ " $repos " != *" $dep "* ]]; then
            repos="$repos $dep"
        fi
    done
fi

base_dir="$HOME/lsp"
# Directory and file names replace "/" in the branch name with "-", as
# new-worktree-set.sh does.
safe_name="${branch_name//\//-}"
set_dir="$base_dir/wt/$safe_name"
any_failed=false

# Without --repos, also remove worktrees of repos outside the default set
# (e.g. gen-epix-R, created with --repos) that the set directory holds.
if [ "$repos_given" = false ] && [ -d "$set_dir" ]; then
    for dest in "$set_dir"/*/; do
        dest="${dest%/}"
        [ -d "$dest" ] && [ ! -L "$dest" ] || continue
        repo="$(basename "$dest")"
        [[ " $repos " == *" $repo "* ]] || repos="$repos $repo"
    done
fi

for repo in $repos; do
    src="$base_dir/$repo"
    dest="$set_dir/$repo"
    if [ ! -d "$dest" ] || [ -L "$dest" ]; then
        dest="$base_dir/${repo}-${safe_name}"
    fi

    [ -d "$dest" ] || continue
    [ -d "$src" ] || continue

    echo "$repo: removing worktree at $dest"
    if [ "$force" = true ]; then
        remove_ok=true
        git -C "$src" worktree remove --force "$dest" || remove_ok=false
    else
        remove_ok=true
        git -C "$src" worktree remove "$dest" || remove_ok=false
    fi

    if [ "$remove_ok" = false ]; then
        echo "  failed to remove -- likely uncommitted changes; use --force to discard them, or commit/stash first" >&2
        any_failed=true
        continue
    fi

    if [ "$delete_branch" = true ]; then
        if git -C "$src" branch -d "$branch_name" 2>&1; then
            echo "  deleted branch $branch_name in $repo"
        else
            echo "  could not delete branch $branch_name in $repo (unmerged? leaving it)" >&2
        fi
    fi
done

# The set directory goes once only symlinks are left in it (a --repos subset
# leaves the other worktrees, and so the directory, in place).
if [ -d "$set_dir" ] && [ -z "$(find "$set_dir" -mindepth 1 -maxdepth 1 ! -type l)" ]; then
    find "$set_dir" -mindepth 1 -maxdepth 1 -type l -delete
    rmdir "$set_dir"
    echo "removed set directory: $set_dir"
fi

workspace_file="$base_dir/lsp-${safe_name}.code-workspace"
if [ "$any_failed" = true ]; then
    echo
    echo "Some worktrees were not removed -- see above. Leaving $workspace_file in place so you can still open it." >&2
    exit 1
fi

if [ -f "$workspace_file" ]; then
    rm "$workspace_file"
    echo "removed workspace file: $workspace_file"
fi
