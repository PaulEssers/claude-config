#!/usr/bin/env bash
# Create a same-named git worktree in each repo of the working set (or an
# explicit --repos list), set up a venv per uv-managed worktree, and write a
# VS Code multi-root workspace pointing at all of them.
#
# Usage:
#   new-worktree-set.sh <branch-name> [--repos repo1,repo2,...] [--no-deps] [--no-venv]
#
# Layout: every set gets a directory of its own, mirroring ~/lsp itself:
#
#   ~/lsp/wt/<branch>/lsp-data        worktree
#   ~/lsp/wt/<branch>/gen-epix-api    worktree
#   ~/lsp/wt/<branch>/lsp-web         symlink -> ~/lsp/lsp-web (not in the set)
#
# so that every literal sibling path "../<repo>" inside a worktree lands on
# the set's own worktree of that repo: [tool.uv.sources] in pyproject.toml
# (uv sync / uv lock / uv export -- which have no override of their own),
# mypy_path, the Makefiles' GEN_EPIX_API_PATH default, the integration-test
# fixtures, and every "../lsp-kubernetes"-style reference in code and docs.
# Repos that are not in the set are symlinked to their canonical checkout, so
# "../<repo>" still resolves exactly as it would from the canonical layout.
#
# For each repo:
#   - if <branch-name> already exists (local or on origin), worktree checks it out.
#   - otherwise, creates a new branch off origin/dev if that repo has
#     a dev branch, otherwise origin/main, and worktrees that.
#
# Editable-install dependencies are auto-added even when not listed
# explicitly: a ticket touching only lsp-data still gets its own
# gen-epix-api worktree, because "../gen-epix-api" would otherwise be the
# symlink to the shared canonical checkout -- which any other agent/session
# may have on an unrelated branch. gen-epix-R gets one too, as a pin of the
# API version it is written against. Pass --no-deps to opt out.
#
# venv setup runs uv for every Python repo (has a pyproject.toml), even ones
# whose canonical checkout is conda-managed (gen-epix-api, idsdb): verified
# 2026-09-18 that neither has a conda-specific binary dependency, only a
# pinned Python version + plain pip requirements files, so uv is a valid
# personal substitute there -- this never touches those repos' own
# README/conda docs, it's purely a private per-worktree choice. Repos with a
# uv.lock (lsp-data, lsp-kubernetes) get `uv sync`; repos without one get
# `uv pip install -e . -r requirements.txt -r dev-requirements.txt` (whichever
# of those files exist), mirroring each repo's own documented pip recipe. A
# repo with a known editable dependency (lsp-data/idsdb -> gen-epix-api) then
# gets that dependency installed with its `server` extra, as the canonical
# checkout's documented `pip install -e "../gen-epix-api[server]"` does.
#
# IMPORTANT: uv respects an already-exported VIRTUAL_ENV over the target
# directory's own project, so every uv invocation here runs with it
# unset (`env -u VIRTUAL_ENV`) to avoid silently touching the wrong venv.
#
# Existing worktree dirs and existing venvs are left untouched (safe to
# re-run / extend a set; a re-run also adds symlinks for repos cloned since).
# Pass --no-venv to skip venv setup entirely.
#
# Sets created before the wt/ layout (~/lsp/<repo>-<branch>) are not touched.
# If one exists for this branch the script stops, since git refuses to check
# out a branch in two worktrees anyway.
#
# Branch names containing "/" (e.g. release/r1) are checked out as-is, but
# any "/" is replaced with "-" when deriving directory/workspace-file names
# (e.g. wt/release-r1, lsp-release-r1.code-workspace), since those names are
# single path components elsewhere in this workspace layout.

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <branch-name> [--repos repo1,repo2,...] [--no-deps] [--no-venv]" >&2
    exit 1
fi

branch_name="$1"
shift

default_repos="gen-epix-api idsdb lsp-data lsp-api lsp-kubernetes"
repos="$default_repos"
add_deps=true
add_venvs=true

while [ $# -gt 0 ]; do
    case "$1" in
        --repos)
            repos="$(echo "$2" | tr ',' ' ')"
            shift 2
            ;;
        --no-deps)
            add_deps=false
            shift
            ;;
        --no-venv)
            add_venvs=false
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# gen-epix-R is no editable install: it calls gen-epix-api over HTTP, but
# gets a worktree of it anyway, to pin the API version (dev at the time the
# set is created) the client is developed against. Having no pyproject.toml,
# it never reaches the venv step's "[server]" install below.
declare -A editable_deps=(
    [lsp-data]="gen-epix-api"
    [idsdb]="gen-epix-api"
    [gen-epix-R]="gen-epix-api"
)

if [ "$add_deps" = true ]; then
    for repo in $repos; do
        dep="${editable_deps[$repo]:-}"
        if [ -n "$dep" ] && [[ " $repos " != *" $dep "* ]]; then
            echo "adding $dep: dependency of $repo (pass --no-deps to skip)"
            repos="$repos $dep"
        fi
    done
fi

base_dir="$HOME/lsp"
# Branch names with slashes (e.g. release/r1) are valid git refs but not
# valid single path components -- sanitize for dir/file naming only, the
# real branch_name (with slashes) is still what git checks out.
safe_name="${branch_name//\//-}"
set_dir="$base_dir/wt/$safe_name"
workspace_file="$base_dir/lsp-${safe_name}.code-workspace"

old_layout=""
for repo in $repos; do
    if [ -d "$base_dir/${repo}-${safe_name}" ]; then
        old_layout="$old_layout $base_dir/${repo}-${safe_name}"
    fi
done
if [ -n "$old_layout" ]; then
    echo "This branch already has a worktree set in the old layout (~/lsp/<repo>-<branch>):" >&2
    for path in $old_layout; do echo "  $path" >&2; done
    echo "Keep using it as is, or remove it first (remove-worktree-set.sh handles both layouts)." >&2
    exit 1
fi

sync_with_fallback() {
    local dest="$1"
    if ! env -u VIRTUAL_ENV uv sync --dev --directory "$dest" 2>&1; then
        echo "  (repo has no 'dev' group, retrying plain 'uv sync')"
        env -u VIRTUAL_ENV uv sync --directory "$dest"
    fi
}

# Fallback for repos with no uv.lock (personal choice to use uv instead of
# conda -- verified 2026-09-18 that gen-epix-api/idsdb have no conda-specific
# binary deps, just a pinned Python version + plain pip requirements files).
# Mirrors each repo's own README recipe generically: editable-install the
# package itself, plus whichever requirements files it actually has.
pip_install_with_fallback() {
    local dest="$1"
    local install_args=(-e .)
    [ -f "$dest/requirements.txt" ] && install_args+=(-r requirements.txt)
    [ -f "$dest/dev-requirements.txt" ] && install_args+=(-r dev-requirements.txt)
    env -u VIRTUAL_ENV uv pip install --directory "$dest" "${install_args[@]}"
}

# Pass 1: create every worktree first, so a dependent repo's venv setup
# (pass 2) can always find its paired dependency worktree already in place.
mkdir -p "$set_dir"
folders_json=""
for repo in $repos; do
    src="$base_dir/$repo"
    dest="$set_dir/$repo"

    if [ ! -d "$src" ]; then
        echo "skip $repo: no such repo at $src" >&2
        continue
    fi

    if [ -L "$dest" ]; then
        # Added to an existing set: replace the symlink to the canonical
        # checkout with a worktree of its own.
        rm "$dest"
    fi

    if [ -d "$dest" ]; then
        echo "$repo: worktree already exists at $dest, leaving as-is"
    else
        # Refresh remote refs so we branch off the current tip and see a
        # recently created dev branch.
        git -C "$src" fetch --quiet origin || echo "$repo: fetch failed, using local remote refs" >&2
        # Prefer dev when the repo has it, otherwise main (origin/HEAD is
        # unreliable now that several repos have both).
        if git -C "$src" show-ref --verify --quiet "refs/remotes/origin/dev"; then
            default_ref="dev"
        else
            default_ref="main"
        fi
        if git -C "$src" show-ref --verify --quiet "refs/heads/$branch_name" \
            || git -C "$src" ls-remote --exit-code --heads origin "$branch_name" >/dev/null 2>&1; then
            echo "$repo: worktree for existing branch $branch_name"
            git -C "$src" worktree add "$dest" "$branch_name"
        else
            echo "$repo: creating new branch $branch_name off origin/$default_ref"
            git -C "$src" worktree add --no-track -b "$branch_name" "$dest" "origin/$default_ref"
        fi
    fi

    # cert/*.pem (mkcert-generated TLS certs, gitignored per checkout) aren't
    # tracked by git, so a fresh worktree starts without them even though the
    # canonical checkout has them -- carry them over so e2e tests that spin up
    # a real TLS server (e.g. gen-epix-api's OAuth test server) don't fail
    # with FileNotFoundError on cert/key.pem or cert/cert.pem.
    if [ -d "$src/cert" ]; then
        mkdir -p "$dest/cert"
        for pem_file in "$src"/cert/*.pem; do
            [ -e "$pem_file" ] || continue
            pem_name="$(basename "$pem_file")"
            if [ ! -f "$dest/cert/$pem_name" ]; then
                cp "$pem_file" "$dest/cert/$pem_name"
                echo "$repo: copied cert/$pem_name from canonical checkout"
            fi
        done
    fi

    folders_json="${folders_json}    { \"name\": \"${repo}\", \"path\": \"wt/${safe_name}/${repo}\" },\n"
done

# Every other canonical checkout in ~/lsp (a directory with a .git directory,
# not a worktree's .git file) becomes a symlink in the set, so "../<repo>"
# resolves for repos the set does not contain.
for src in "$base_dir"/*/; do
    src="${src%/}"
    repo="$(basename "$src")"
    [ -d "$src/.git" ] || continue
    [ -e "$set_dir/$repo" ] && continue
    ln -s "$src" "$set_dir/$repo"
done

folders_json="${folders_json}    { \"name\": \"notes\", \"path\": \"notes\" },\n"
folders_json="${folders_json%,\\n}"
printf '{\n  "folders": [\n%b\n  ],\n  "settings": {}\n}\n' "$folders_json" > "$workspace_file"

# Pass 2: venv setup, now that every worktree in the set exists.
if [ "$add_venvs" = true ]; then
    echo
    echo "Setting up venvs..."
    for repo in $repos; do
        dest="$set_dir/$repo"
        [ -d "$dest" ] && [ ! -L "$dest" ] || continue

        if [ ! -f "$dest/pyproject.toml" ]; then
            echo "$repo: no pyproject.toml -- not a Python project, nothing to install"
            continue
        fi

        if [ -d "$dest/.venv" ]; then
            echo "$repo: venv already exists, leaving as-is"
            continue
        fi

        required_python="$(grep -m1 '^requires-python' "$dest/pyproject.toml" | grep -oE '[0-9]+\.[0-9]+' | head -1)"
        echo "$repo: creating venv${required_python:+ (python $required_python)}"
        if [ -n "$required_python" ]; then
            env -u VIRTUAL_ENV uv venv --directory "$dest" --python "$required_python"
        else
            env -u VIRTUAL_ENV uv venv --directory "$dest"
        fi

        if [ -f "$dest/uv.lock" ]; then
            sync_with_fallback "$dest"
        else
            echo "  (no uv.lock -- installing via requirements files instead of conda)"
            pip_install_with_fallback "$dest"
        fi

        # "../<dep>" already is the set's own worktree (or, with --no-deps,
        # the symlink to the canonical checkout); this only adds the extra.
        dep="${editable_deps[$repo]:-}"
        if [ -n "$dep" ] && [ -d "$set_dir/$dep" ]; then
            echo "$repo: installing $dep with its server extra"
            env -u VIRTUAL_ENV uv pip install -e "../${dep}[server]" --directory "$dest"
        fi
    done
fi

echo
echo "Set directory:     $set_dir"
echo "Workspace written: $workspace_file"
echo "Open with: code \"$workspace_file\""
