# Critic binding: subagent

The default critic binding for the loop's adversarial review slot.
The manifest (`../manifest.json`) names it: `"critic": "subagent"`.

## How to invoke

Spawn a **fresh, clean-context subagent** (the Task tool in either
harness). Do not run the critic in the calling session and do not reuse
a subagent that has seen the code being reviewed: the critic's value is
a context with no investment in the diff. Clean context means no prior
discussion and no stake, not file-blindness.

Give the subagent, as its entire input:

1. this directory's `critic-prompt.md` as its instructions,
2. the unified diff of the PR range
   (`git -C <repo> diff <resolved-base>...<resolved-head>`),
3. the task brief file, so it knows what the change claimed to do,
4. the prior rounds' dispositions (fixed, rejected, and accepted
   findings with their evidence, from the Dispositions blocks of the
   previous round comments): re-flagging a dispositioned finding
   without materially new evidence is out of contract.

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
