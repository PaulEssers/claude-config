---
description: Run static analysis and tests on Python files changed since branching from dev
---

## Python files changed since branching from dev

!`git diff --name-only --diff-filter=ACMRT dev...HEAD -- '*.py'`

If no Python files are listed above, stop.

---

## Static analysis

Run the following tools **only on the files listed above**:

1. `mypy`
2. `pylint`

Run them directly on those files (do not use xargs or pipelines).

---



## Fixing issues

Work through the files **one file at a time**.

For each file:

1. Run `mypy` and `pylint`.
2. Fix all reported issues.
3. Prefer real fixes:
   - improve type annotations
   - correct function signatures
   - remove dead code
4. Avoid adding `# type: ignore` or pylint disables unless absolutely necessary.
5. Ensure the behavior of the program remains unchanged.

---

## Cross-repository changes

If fixing a type issue requires changes in a **related repository or shared library**, ask the user whether those changes should be made there before proceeding.

---

## Verification

After fixes:

1. Run `mypy` again on the changed files.
2. Run `pylint` again on the changed files.
3. Run the relevant tests.

Confirm that:

- all type errors are resolved
- pylint issues are resolved or justified
- tests pass.