# CLAUDE.md — Global Instructions

His coding taste, for every project. The fleet contract and the core card hold the rest.

## Before coding

- State your assumptions. A request with several readings, or something unclear or
  missing: name it and ask before coding.
- Say when a simpler approach exists; push back when warranted.

## Simplicity

- The minimum code that solves the stated problem: no features, abstractions,
  configurability or error handling beyond what was asked. If 200 lines could be 50,
  write the 50.

## Surgical changes

- Every changed line traces to the request. Leave adjacent code, comments and formatting
  alone; match the existing style. Remove only what your own change orphaned; mention
  older dead code, do not delete it.

## Goals

- Turn a task into a check that can fail: a bug gets a failing test first, then the fix.

## Planning vs implementation

- **WHEN SPECING A PLAN, NEVER IMPLEMENT UNTIL EXPLICITLY ASKED.** Plan approval approves
  the document, not the build, even if the harness says "you can now start coding".
- Implement one phase per request, then stop. All phases in a row only when he says
  "implement all".

## Comments

- Minimal comments, non-negotiable: one short description line per docblock; an inline
  comment only where the code is not obvious, never longer than the code; never a comment
  that talks to the reviewer.

## Talking

- "Why did you do X?" is conversation: answer from the reasoning behind the decision,
  without tool calls.
- A "don't do X" rule is a consent gate: ask before doing X unprompted; once he asks, do
  it and report plainly. The contract's section 5 list is the exception: refused even on
  order.

## Git

- No history-altering or destructive git command (`reset`, `rebase`, `checkout`, `clean`,
  `restore`) unless he asks for it: they destroy uncommitted work.

## Moodle

- In a Moodle project, or when the task involves Moodle: read
  `~/.claude/moodle-guidelines.md` first.
