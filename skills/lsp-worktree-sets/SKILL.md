---
name: lsp-worktree-sets
description: >-
  Create, extend, audit, move and remove per-ticket git worktree sets for the
  gen-epix/LSP repos under ~/lsp (gen-epix-api, idsdb, lsp-data, lsp-api,
  lsp-kubernetes, gen-epix-R). A set is ~/lsp/wt/<branch>/ with a worktree per
  repo the ticket touches plus its editable-install dependencies, a uv venv per
  Python worktree, and a generated ~/lsp/lsp-<branch>.code-workspace. Use when
  asked to start work on a ticket in its own workspace/worktrees, add a repo to
  an existing set, check which sets are finished, clean up or remove a set, or
  move an old-layout (~/lsp/<repo>-<branch>) set into wt/.
argument-hint: 'e.g. "new LSP-4129", "remove LSP-4087-...", "audit"'
---

# LSP worktree sets

`gen-epix-api` is an editable install shared by `lsp-data` and `idsdb`, so a
single checkout of it couples every ticket to whatever branch it is on. Each
parallel ticket therefore gets its own **worktree set**: the same branch
checked out in every repo it touches *plus* their editable-install
dependencies, in a directory of its own so that every `../<repo>` path inside
a worktree reaches the set's own copy.

```
~/lsp/wt/<branch>/lsp-data        worktree
~/lsp/wt/<branch>/gen-epix-api    worktree (dependency of lsp-data, auto-added)
~/lsp/wt/<branch>/lsp-web         symlink -> ~/lsp/lsp-web (not in the set)
~/lsp/lsp-<branch>.code-workspace generated VS Code workspace
```

The scripts live next to this file in `scripts/`; `~/lsp/scripts` is a
symlink to that directory, so `~/lsp/scripts/<name>.sh` works too. Day-to-day
reference: `~/lsp/notes/docs/workspace_setup.md`. Rationale and gotchas:
`~/lsp/notes/investigations/git-worktrees.md`.

## Creating a set for a ticket

1. **Find the ticket** to learn which repos it touches and to pick a name:
   `grep -n "<KEY>" ~/lsp/notes/tickets/INDEX.md` (the Repos column), then the
   draft `~/lsp/notes/tickets/<KEY>-*.md` and its plan in `~/lsp/notes/plans/`.
   If there is no draft, ask the user which repos, or use the default set.
2. **Check for an existing branch or set** — reuse it instead of inventing a
   second name: `ls ~/lsp/wt/`, `ls -d ~/lsp/*-<KEY>*`, and
   `git -C ~/lsp/<repo> branch -a | grep -i <KEY>` in each repo.
3. **Name the branch** `<KEY>-<short-kebab-summary>`: the Jira key, then 3–6
   words saying what the change does (e.g. `LSP-4129-preserve-remote-http-status`,
   `LSP-4126-remove-duplicate-landing-zone-enum`). Match the style of the
   existing names in `~/lsp/wt/`.
4. **Run** (takes a few minutes: it builds the venvs):

   ```bash
   ~/lsp/scripts/new-worktree-set.sh <branch> --repos <repo1>,<repo2>
   ```

   - Without `--repos`: `gen-epix-api idsdb lsp-data lsp-api lsp-kubernetes`.
   - Dependencies are auto-added (`lsp-data`/`idsdb`/`gen-epix-R` →
     `gen-epix-api`); `--no-deps` opts out, `--no-venv` skips the venvs.
   - Repos outside the default set (`gen-epix-R`) only via `--repos`.
   - An existing branch (local or on `origin`) is checked out as is;
     otherwise a new one is cut from `origin/dev`, or `origin/main` if the
     repo has no `dev`.
   - Safe to re-run: to add a repo to an existing set, run it again with that
     repo in `--repos`.
5. **Verify and report**: `ls -la ~/lsp/wt/<branch>/` and the HEAD of each
   worktree (`git -C ~/lsp/wt/<branch>/<repo> log --oneline -1`). Tell the user
   the branch name, the repos, the base commits, and how to open it:
   `code ~/lsp/lsp-<branch>.code-workspace`.

## Finishing a ticket

```bash
~/lsp/scripts/audit-worktree-sets.sh       # report only; --no-fetch, --no-pr to skip network
~/lsp/scripts/remove-worktree-set.sh <branch>                  # refuses on uncommitted changes
~/lsp/scripts/remove-worktree-set.sh <branch> --delete-branch  # also safe `git branch -d`
```

- The audit removes nothing. It marks a set removable only when every
  worktree's HEAD is in the default branch (ancestor, squash, merged PR or
  cherry-pick) with no uncommitted files or stashes, and prints the remove
  commands for those sets.
- Removing deletes worktrees and venvs: **confirm with the user first**, and
  never add `--force` (discards uncommitted changes) on your own.
- `--delete-branch` refuses a branch merged into `dev` when the canonical
  checkout is on another branch (`git branch -d` checks that checkout's HEAD).
  If `git rev-list --count origin/dev..<branch>` is 0, tell the user it is
  safe to delete with `-D`; don't do it unasked.

## Moving an old-layout set

Sets created before 2026-10-21 live at `~/lsp/<repo>-<branch>`. To move one
into `wt/` (keeps uncommitted changes, recreates venvs, copies Claude Code
sessions to the new project path):

```bash
~/lsp/scripts/move-worktree-set.sh <branch>
```

Run it from outside the set, with no VS Code window or Claude Code session
open on it — this session included, if its working directory is in the set.

## Gotchas

- **Dependency-only worktrees are pins**, not for development. Refresh one
  with `git -C ~/lsp/wt/<branch>/gen-epix-api pull --ff-only origin dev`.
- **Plain `uv sync` in a worktree** can repoint the editable `gen-epix-api`
  install back to the canonical checkout; and an exported `VIRTUAL_ENV`
  overrides cwd-based venv detection. The scripts run uv with
  `env -u VIRTUAL_ENV` for that reason; do the same when running uv by hand.
- **One SQL Server for all sets**: `make start-db` uses the same Compose
  project from every set. Don't run two integration suites at once.
- **Stale `origin/HEAD`** can make a repo's default branch detect wrong
  (`git remote set-head origin -a` fixes it).
