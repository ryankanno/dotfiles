# Critic binding: subagent

The default critic binding for the loop's adversarial review slot.
The manifest (`../manifest.json`) names it: `"critic": "subagent"`.

## How to invoke

Spawn a **fresh, clean-context subagent** (the Task tool in either
harness). Do not run the critic in the calling session and do not reuse
a subagent that has seen the code being reviewed: the critic's value is
a context with no investment in the diff. Clean context means no prior
discussion and no stake, not file-blindness.

Give the subagent, as its entire input and inline in its prompt, not
as files for it to read: every read is one more turn over the whole
context, and the context is what costs (measured on PR 40: the round 9
critic's first turn cost 32k tokens before it read anything, and it
grew to 98k by its fourteenth):

1. this directory's `critic-prompt.md` as its instructions,
2. the unified diff to attack: in round 1, the whole PR range
   (`git -C <repo> diff <resolved-base>...<resolved-head>`); from round
   2 on, only the delta since the prior round's head
   (`git -C <repo> diff <range.prior_head> <headRefOid>`, both from
   `round.json`). Code outside the delta was reviewed in earlier rounds
   and a finding there can only be a follow-up, so handing the critic
   the whole PR again buys nothing that changes the round (measured on
   PR 40: 1.0M to 2.4M tokens per refine round, with the delta 8 to 28
   percent of the full diff),
3. the task brief file, so it knows what the change claimed to do,
4. the prior rounds' dispositions (fixed, rejected, and accepted
   findings with their evidence, from the Dispositions blocks of the
   previous round comments): re-flagging a dispositioned finding
   without materially new evidence is out of contract, and from round 2
   on the Fixed lines are what the delta claims to fix. Only those three
   kinds of line: never a round's follow-ups or any follow-up register.
   A follow-up cannot block, so a critic handed them re-raises them and
   spends turns that change nothing (round 9 on PR 40: 7 of its 10
   findings were register items).

The subagent also gets **read access to the repository at the PR head
SHA** (`git -C <repo> show <headRefOid>:<path>`), so it can verify
behavior claims against the code that produces them. It reads no prior
discussion, no comments, no round history.

## Output contract

The subagent returns numbered findings, each carrying:

- file and line in the diff's terms,
- the claim: what is broken, incorrect, or missing,
- the break: how it fails, concretely,
- severity: high, medium, or low,
- for any claim about what renders or happens at runtime: the file and
  line of the code that produces it. A behavior claim it cannot cite
  from the code is reported as unverifiable, not asserted.

Findings that do not reference the diff are out of contract and are
dropped by the caller. An empty findings list is a valid result.

## Swapping this binding

A different critic (a static analyzer, a second reviewer tool, an
external service) is a new directory under `tools/` with the same
invocation and output contract, plus one manifest line. The skills
never name this binding's internals.
