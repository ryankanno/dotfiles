# Final report: <title>

- **Task:** <source locator> | <title>
- **PR:** <PR URL>
- **Draft:** <no | yes (the loop did not end clean or converged) | yes (`gh pr ready` failed: <its error>)>
- **Verdict:** <clean | converged | capped-unrecovered | blocked (<reason>)>

## Rounds

| Round | SHA | Verdict | Run by | Comment |
|---|---|---|---|---|
| <N> | <short SHA> | <round verdict> | <implementer or human> | <comment URL, or the draft path on a repository that is not owned> |

## Ratification

| Item (step 6) | Result |
|---|---|
| 1. The reviewed head is the PR's head | <holds, or what failed> |
| 2. The newest round reviewed the whole PR | <holds, or what failed> |
| 3. The round's comment is on the PR (or its scanned draft, on a repository that is not owned) | <holds, or what failed> |
| 4. The gate is green on the PR's code | <holds, or what failed> |
| 5. Every Rejected and Accepted disposition holds | <holds, or what failed> |
| 6. The orchestrator's own read of the diff | <holds, or each problem it found> |

Overruled dispositions: <each finding and the reason, or "None.">

## Accepted judgment calls

<Every Accepted line from the Dispositions blocks, verbatim, or "None.">

## Follow-ups

<The final round comment's Follow-ups section, verbatim, or "None.">

## Gate

- **Command:** `<gate words from intake>`
- **Final result:** <exit code and the last lines it printed>

## Scan blocks

<Each blocked post and the line the scan caught, or "None.">

## Cost

- **Reviewer:** <the newest round comment's Cost line: the
  `cumulative_tokens` its round.json carried when it was written>;
  sessions <session ids>. <A rerun of an earlier round afterwards does
  not recompute later rounds' round.json: say so plainly when one
  happened.>
- **Critic:** <the critic's tokens summed from every round comment's
  Cost line (on a repository that is not owned, each round's
  `comment.md`)>. <Name any round whose critic tokens were not
  reported.>
- **Bindings:** reviewer <binding>, critic <binding>, ocr <version>
