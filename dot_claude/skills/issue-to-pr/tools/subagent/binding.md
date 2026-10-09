# Critic binding: subagent

The default critic binding for the loop's adversarial review slot.
The manifest (`../manifest.json`) names it: `"critic": "subagent"`.

## How to invoke

Spawn a **fresh, clean-context subagent** (the Task tool in either
harness). Do not run the critic in the calling session and do not reuse
a subagent that has seen the code being reviewed: the critic's value is
a context with no investment in the diff. Clean context means no prior
discussion and no stake, not file-blindness.

The subagent's prompt is the output of this directory's
`critic-input.sh`, passed verbatim: no paraphrase, no summary, no
added or removed instruction, no input left on disk for it to read.

```bash
$HOME/.claude/skills/issue-to-pr/tools/subagent/critic-input.sh \
  --repo <checkout-dir> --round-dir <round-dir> --brief <brief-file>
```

The script emits `critic-prompt.md` verbatim, then inline: the brief,
from round 2 on the blocking findings of the newest round comment (what
this round's diff answers), the standing Rejected and Accepted lines,
the repository path for verifying claims, and the unified diff the
reviewer reviewed (the whole PR in round 1 or on an empty delta, the
delta since the prior round's head otherwise). Follow-ups never reach
the critic: a follow-up cannot block, so a critic handed them re-raises
them and spends turns that change nothing. The script also keeps the
prompt as `critic-input.md` in the round directory, so the round's
record shows what the critic was told.

Why a script and not a recipe: a caller writing its own prompt drifted
from the rules (measured on PR 40, round 11: the refine dropped the
high-only rule for code outside the delta, wrote that re-raising
follow-ups is "not out of bounds", and pointed the critic at a
dispositions file three rounds stale), and every input left on disk
cost the critic a turn over its whole context (round 9: 32k tokens on
the first turn, 98k by the fourteenth).

## Output contract

The subagent returns numbered findings, each carrying:

- file and line in the diff's terms,
- the claim: what is broken, incorrect, or missing,
- the input, state or sequence that reaches it and the observable harm,
- severity: high, medium, or low,
- how it checked, and for any claim about what renders or happens at
  runtime the file and line of the code that produces it.

Then a final "Unconfirmed candidates" section: suspicions it could not
ground that way, one line each with what is missing. The caller shows
that section verbatim in the collapsed critic block and never counts
it: an unconfirmed candidate is neither a blocking finding nor a
follow-up. This is the evidence bar the earlier refine loop
converged on; the adversarial "prove otherwise"
framing it replaces produced at least one medium every round on PR 40.

Findings that do not reference the diff are out of contract and are
dropped by the caller — with one exception, the high on code outside
the delta: the critic reports it with the repository file and line,
and it blocks. An empty findings list is a valid result.

## Swapping this binding

A different critic (a static analyzer, a second reviewer tool, an
external service) is a new directory under `tools/` with the same
invocation and output contract, plus one manifest line. The skills
never name this binding's internals.
