# Grilling: settling decisions before a spec document is written

Adapted from the grilling skill of mattpocock/skills. spec-author runs as a subagent and cannot ask the user anything, so any decision it is not given becomes a guess in the document. The phase skill runs this interview in the main context first and hands the result to spec-author as `DECISIONS`.

## 1. Scope

- Ask only about facts the document being written owns (`doc-format.md` §1):
  - request-spec: the requests and the out-of-scope list
  - requirements: acceptance criteria, NFR numbers and journeys
  - design: the Decisions and the component split

  A question whose answer belongs to a later document waits for that phase.
- Ask a question only if the answer changes what the document says. When every plausible answer leads to the same text, do not ask.
- `MODE: create` runs the full interview. `MODE: revise` asks only about decisions that the upstream diff or the review comments reopen. When they reopen none, skip the interview.

## 2. The decision tree

Lay the decisions out as a tree: each decision branches into the decisions that depend on it. The **frontier** is every open decision whose prerequisites are all settled.

## 3. Rounds

1. Ask the whole frontier in one round, in the user's language, as text. Do not use AskUserQuestion here, because a frontier often has more questions than it allows. Format:

   ```
   ❓ **Q1** - **<title>**: <the question, with the options when there are some>

   ➡️ <recommended answer and its one-line reason>

   ---

   ❓ **Q2** - ...
   ```

2. A question that depends on another question still open in this round goes to a later round.
3. Wait for the answers. Mark those decisions settled, recompute the frontier, and ask the next round.

## 4. Facts and decisions

- Finding facts is your job, never the user's. When a question needs a fact from the environment (code, tests, library behaviour), look it up instead of asking:
  - From Phase 1 on, read the evidence under `evidence/`.
  - In Phase 0, or when the evidence lacks the fact (`legacy` has no evidence), launch a read-only `Explore` subagent.
- Do not block the round on a lookup. Only the questions downstream of the running lookup wait; ask the rest now.
- A Phase 0 lookup only shapes the questions and the recommended answers. The facts it finds are owned by the Phase 0.5 evidence and are not written into request-spec.
- Decisions belong to the user. Put each one to them and wait; never settle one on the user's behalf.

## 5. End

1. The interview ends when the frontier is empty and nothing is left silently assumed.
2. Show the settled decisions as a numbered list and ask the user to confirm it.
3. After the user confirms, pass that list to spec-author as `DECISIONS`.
4. When spec-author reports `open_decisions`, put them to the user as one more round. Then launch spec-author again with `MODE: revise` and the extended list.
