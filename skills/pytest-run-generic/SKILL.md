---
name: pytest-run-generic
description: >-
  Run pytest ONCE to a captured log file, then inspect that file repeatedly with
  grep/sed/awk instead of re-running pytest for every question (which failed, why,
  the summary line, warnings). Personal, repo-agnostic fallback for projects that
  don't have a repo-specific version of this skill. Use when: running more than one
  pytest invocation to look at different aspects of the same test run; iterating on
  a failure and about to re-run pytest just to re-read output already seen; asked to
  check test status, failures, tracebacks, or warnings after a run. Do NOT use to
  decide whether a fresh run is needed — rerun pytest for real whenever source or
  test code changed since the last capture.
argument-hint: 'Optional: pytest target/args, e.g. "tests/test_foo.py -k bar"'
---

# Pytest Run (capture once, inspect many times)

Running `pytest` repeatedly with different `-k`/piped-grep/verbosity flags to answer
different questions about the *same* test run is slow and wasteful. Run it once,
capture full output to a file, then answer every follow-up question by reading that
file.

## When to use

- About to run pytest a second (or third) time only to look at a different slice of
  the *same* underlying run (e.g. first `| grep FAILED`, then
  `| grep -A20 "test_foo"`, then `| tail -30` for the summary).
- Need to check several things after one run: which tests failed, a specific
  traceback, pass/fail counts, deprecation warnings.

## When NOT to use (rerun for real)

- Source or test code changed since the last capture — the log is stale.
- Need a different test selection (`-k`, a different path, different markers) than
  what's in the existing log — that's a new run, not a new grep.

## Method

1. **Pick an output directory** the project already ignores in git — check for an
   existing gitignored scratch dir (`tmp/`, `.tmp/`, `.cache/`, `/tmp` as a fallback
   if the repo has no convention). Capture once:

   ```bash
   pytest <target> -v --tb=long -ra > <scratch-dir>/pytest-run.log 2>&1; echo "exit: $?"
   ```

   - Swap `<target>` for whatever the user actually asked to test (a file, `-k EXPR`,
     a marker, or the default test path) — this is still a single capture.
   - `-v` prints one PASSED/FAILED/ERROR line per test (needed to grep by test
     name). `--tb=long` keeps full tracebacks in the file so a second run isn't
     needed just to see more context. `-ra` adds a short summary block at the end
     with reasons for skips/xfails. Drop/adjust flags the project's own pytest
     config already sets via `addopts` to avoid conflicting duplicates.
   - The `> ... 2>&1` redirect may not be in a pre-approved command allowlist in
     every project — expect a possible one-time permission prompt.
   - Echoing `$?` captures the exit code even though the file redirect swallows
     pytest's own screen output.

2. **Inspect the file** with plain text tools, as many times as needed, without
   touching pytest again:

   ```bash
   # overall result + summary block (bottom of output)
   tail -40 <scratch-dir>/pytest-run.log

   # just the failed/errored test node IDs
   grep -E "^(FAILED|ERROR) " <scratch-dir>/pytest-run.log

   # full traceback for one test
   grep -n "test_name_here" <scratch-dir>/pytest-run.log
   sed -n '120,180p' <scratch-dir>/pytest-run.log   # use the line number from above

   # warnings
   grep -A3 "warnings summary" <scratch-dir>/pytest-run.log

   # pass/fail/error counts only
   grep -E "^[0-9]+ (passed|failed|error|skipped)" <scratch-dir>/pytest-run.log
   tail -1 <scratch-dir>/pytest-run.log
   ```

3. **Only re-run pytest** when a code change happened, a different test selection
   is needed, or the log file doesn't exist yet.

## Notes

- One fixed filename (`pytest-run.log`) is intentional: it's per-session scratch,
  not a history — each new capture overwrites the last. Use a second filename only
  if two runs genuinely need to be compared side by side.
- Respect the project's own marker/config conventions (deselected markers, custom
  `addopts`, `testpaths`) — check `pyproject.toml` / `pytest.ini` / `setup.cfg`
  before assuming defaults.
- This skill is for *iterating* on a single run's output, not a replacement for the
  project's real final verification step (its actual CI/test command) before
  calling work done.
- If a repo has its own project-specific version of this skill (tuned to its
  scratch-dir convention, markers, and CI invocation), prefer that one — it takes
  precedence over this personal fallback automatically when installed at the
  project level under a different name, or shadows it entirely if given the same
  name.
