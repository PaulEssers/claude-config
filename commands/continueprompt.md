---
description: Write a prompt to continue in a fresh window
---

Write a prompt to start the work (if we just made a plan) or continue the work on a plan
in a fresh context window. 

Build the prompt as such:
1. State the goal of the work we are doing
2. Point the agent to the markdown file containing the plan, if it exists
3. Briefly reiterate the plans phases and mark if they are done or not.
4. Instruct the agent to continue work on the next to-do phase. 

Instruct the agent to after completing each phase:
1. Run the relevant tests (see Verification section of the plan); fix any failures before moving on
2. Run `isort --profile black . && black .` to format
3. After each phase, write a conventional commit message for the changes made in that phase (do not commit — just output the message and wait for the user to give a go-ahead before starting the next phase)


Guidelines:
1. Do not look up any additional information, use only the context you currently have.
2. Exclude any reference to errors or mistakes that we have already fixed and are no longer
relevant, unless it is to prevent them not making the same mistake again.

Extra instructions for the agent:
- Run commands synchronously and wait for them to complete.
- Do NOT run commands in the background.
- Do NOT poll output files.
- Wait for the final output before responding.