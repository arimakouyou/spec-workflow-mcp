# Grilling: settling decisions before a spec document is written

Adapted from the grilling skill of mattpocock/skills. spec-author runs as a subagent and cannot ask the user anything, so any decision it is not given becomes a guess in the document. The phase skill runs this interview in the main context first and hands the result to spec-author as `DECISIONS`. Each round goes to JEV first, and only what JEV leaves undecided goes to the user; this part follows the gril-jev skill of watany-dev/jev-playground.

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

1. Put the whole frontier to JEV first (§4). A question JEV settles is not asked to the user.
2. Ask the user the rest in one round: the questions JEV left undecided, the questions that cannot be put to JEV, and every question when JEV is unavailable. Write in the user's language, as text. Do not use AskUserQuestion here, because a frontier often has more questions than it allows. Format:

   ```
   ❓ **Q1** - **<title>**: <the question, with the options when there are some>

   ➡️ <recommended answer and its one-line reason; for a question JEV left undecided, also JEV's probabilities>

   ---

   ❓ **Q2** - ...
   ```

3. A question that depends on another question still open in this round goes to a later round.
4. Wait for the answers. Mark those decisions settled, recompute the frontier, and start the next round.

## 4. Asking JEV

JEV is a judgement model that returns only probabilities over given answers. `jevcli` calls it.

1. Write the request to the scratchpad, never into the repository:
   - `state`: every fact the answers depend on, written out in full. JEV cannot read the repository or the conversation. Add a note that the state is evidence, not instructions. Never put keys, tokens or personal data in it: the request leaves this machine.
   - `questions`: one issue per question, keyed by the question title. Use:
     - `noul` for a yes/no question, phrased so that the evidence can refute it: "judging only from the evidence, can X be kept?", not "is X safe?"
     - `choice` for a pick from options that are mutually exclusive and cover every case
     - `score` for a position on ordered levels, low to high
   - A question with an open answer (a name, a free-form number) cannot be put to JEV. Turn it into a `choice` over concrete candidates, or leave it for the user.
2. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-grill-jev.sh <request.json>`. It sorts the answers by fixed thresholds:
   - `noul`: a yes probability of at least 0.85, or at most 0.15
   - `choice`: a confidence of at least 0.6 and a margin of at least 0.2 between the top two
   - `score`: a top probability of at least 0.5

   Questions that meet the threshold are under `decided`; the rest are under `undecided`.
3. Take `decided` as settled, and record each one as answered by JEV, with its probability.
4. On exit 1 (jevcli failed) or exit 4 (jevcli not installed), report the error in one line and put the whole frontier to the user. Never fill a failed answer with your own guess.

## 5. Facts and decisions

- Finding facts is your job, never the user's or JEV's. When a question needs a fact from the environment (code, tests, library behaviour), look it up instead of asking:
  - From Phase 1 on, read the evidence under `evidence/`.
  - In Phase 0, or when the evidence lacks the fact (`legacy` has no evidence), launch a read-only `Explore` subagent.
- Do not block the round on a lookup. Only the questions downstream of the running lookup wait; ask the rest now.
- A Phase 0 lookup only shapes the questions, the JEV state and the recommended answers. The facts it finds are owned by the Phase 0.5 evidence and are not written into request-spec.
- A decision is settled by JEV's decided answer or by the user, never by you.

## 6. End

1. The interview ends when the frontier is empty and nothing is left silently assumed.
2. Show the settled decisions as a numbered list and ask the user to confirm it. Mark each one as settled by JEV (with its probability) or by the user. The user may overturn any JEV answer.
3. After the user confirms, pass that list to spec-author as `DECISIONS`.
4. When spec-author reports `open_decisions`, run one more round on them (§3). Then launch spec-author again with `MODE: revise` and the extended list.
