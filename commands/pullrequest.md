---
description: Generate a GitHub CLI command to create a PR to dev using ticket info and plan notes
---

## Determine the current branch

!`git branch --show-current`

## Extract ticket ID (LSP-XXXX)

!`git branch --show-current | grep -oE 'LSP-[0-9]+' || true`

## Show commits in this branch (full commit messages)

!`git log dev..HEAD --pretty=format:"---%ncommit: %h%nsubject: %s%n%n%b%n"`

## Look for plan notes

The ticket ID was extracted above (e.g. LSP-3098). The current branch name was shown above.

Use the Glob tool to search for a matching plan file. Try these two locations, substituting the actual ticket ID:

1. `notes/plans/<LSP-ID>-*.md` (relative to repo root)
2. `/mnt/c/Users/PaulEssers/OneDrive - Gimix B.V/Documents/Obsidian/Learning/Projects/RIVM/repos/gen-epix/<repo-name>/notes/plans/<LSP-ID>-*.md`

Where `<repo-name>` is the last segment of the git repo root (e.g. `idsdb`).

If a matching file is found, read its contents.

## Task

Prepare a command using the GitHub CLI to create a pull request in GitHub.

Requirements:

1. Base branch must be `dev`.
2. Head branch must be the **current branch**.
3. PR **title must be a one line summary of the goal**.
4. Extract the ticket ID `LSP-XXXX`.
5. If a matching `notes/plans/LSP-XXXX-*.md` file exists:

   * use its markdown content to help generate the PR description.
6. Also consider the commits and changed files.

## Description rules

Generate a concise Markdown description:

* **Maximum 20 lines**
* Prefer information from the `notes/plans` document if available.
* Supplement with commit information if needed.

Use this structure:

```markdown
## Summary
Short explanation of the change.

## Changes
- Key change 1
- Key change 2
- Key change 3

## Notes
Anything reviewers should be aware of.
```

## Output format

Produce **one ready-to-run command**:

```
gh pr create \
  --base dev \
  --head <current-branch> \
  --title "<branch-name>" \
  --body "<generated markdown description>"
```

Constraints:

* The description must not exceed **20 lines**.
* Escape quotes so the command can be pasted directly into a shell.
* **Do not execute the command**. Only print it.
