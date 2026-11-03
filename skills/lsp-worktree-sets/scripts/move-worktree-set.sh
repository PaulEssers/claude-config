#!/usr/bin/env bash
# Move a worktree set from the old layout (~/lsp/<repo>-<branch>) to the
# current one (~/lsp/wt/<branch>/<repo>), keeping everything in the
# worktrees: uncommitted and staged changes, an unfinished merge, untracked
# files. See new-worktree-set.sh for why the layout changed.
#
# Usage:
#   move-worktree-set.sh <branch-name>
#
# For every repo that has ~/lsp/<repo>-<branch>:
#   - deletes its .venv (a venv records its absolute path, so it cannot move),
#   - `git worktree move`s it into ~/lsp/wt/<branch>/<repo>,
#   - removes GEN_EPIX_API_PATH / MYPYPATH from its .claude/settings.local.json
#     (they pointed at the old paths, and the new layout does not need them),
#   - copies its Claude Code sessions to the folder Claude Code uses for the
#     new path, so `claude --resume` there lists them (the originals stay).
# Then runs new-worktree-set.sh for the moved repos (--no-deps, so the set
# keeps exactly the repos it had), which adds the symlinks, rewrites the
# workspace file and recreates the venvs.
#
# Run it from outside the set, with no VS Code window or Claude Code session
# open on it: both would keep using the old paths.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <branch-name>" >&2
    exit 1
fi

branch_name="$1"
base_dir="$HOME/lsp"
script_dir="$(dirname "$(readlink -f "$0")")"
safe_name="${branch_name//\//-}"
set_dir="$base_dir/wt/$safe_name"
claude_projects="$HOME/.claude/projects"

# Claude Code names a project's folder after its path, with every character
# that is not a letter or digit replaced by "-".
claude_project_dir() {
    echo "$claude_projects/$(echo "$1" | sed 's/[^a-zA-Z0-9]/-/g')"
}

old_dirs=()
for src in "$base_dir"/*/; do
    src="${src%/}"
    repo="$(basename "$src")"
    [ -d "$src/.git" ] || continue
    old="$base_dir/${repo}-${safe_name}"
    [ -f "$old/.git" ] && old_dirs+=("$old")
done

if [ ${#old_dirs[@]} -eq 0 ]; then
    echo "No old-layout worktrees for $branch_name (~/lsp/<repo>-$safe_name)." >&2
    exit 1
fi

current_dir="$(pwd -P)"
for old in "${old_dirs[@]}"; do
    if [[ "$current_dir/" == "$old/"* ]]; then
        echo "Run this from outside $old (cd ~ first)." >&2
        exit 1
    fi
done

mkdir -p "$set_dir"
moved_repos=()
for old in "${old_dirs[@]}"; do
    repo="$(basename "$old")"
    repo="${repo%-"$safe_name"}"
    src="$base_dir/$repo"
    dest="$set_dir/$repo"

    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        echo "$repo: $dest already exists, leaving $old where it is" >&2
        continue
    fi
    [ -L "$dest" ] && rm "$dest"

    if [ -d "$old/.venv" ]; then
        echo "$repo: deleting .venv (recreated after the move)"
        rm -rf "$old/.venv"
    fi

    echo "$repo: moving $old -> $dest"
    git -C "$src" worktree move "$old" "$dest"
    moved_repos+=("$repo")

    settings="$dest/.claude/settings.local.json"
    if [ -f "$settings" ]; then
        jq 'if .env then .env |= del(.GEN_EPIX_API_PATH, .MYPYPATH) else . end
            | if .env == {} then del(.env) else . end' "$settings" > "$settings.tmp"
        mv "$settings.tmp" "$settings"
        echo "$repo: removed GEN_EPIX_API_PATH / MYPYPATH from .claude/settings.local.json"
    fi

    old_sessions="$(claude_project_dir "$old")"
    if [ -d "$old_sessions" ]; then
        new_sessions="$(claude_project_dir "$dest")"
        mkdir -p "$new_sessions"
        cp -a --update=none "$old_sessions"/. "$new_sessions"/
        echo "$repo: copied Claude Code sessions to $new_sessions"
    fi
done

if [ ${#moved_repos[@]} -eq 0 ]; then
    echo "Nothing moved." >&2
    exit 1
fi

echo
repos_csv="$(IFS=,; echo "${moved_repos[*]}")"
"$script_dir/new-worktree-set.sh" "$branch_name" --repos "$repos_csv" --no-deps
