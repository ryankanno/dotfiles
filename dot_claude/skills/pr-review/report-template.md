# The standard review report comment

Shared by /pr-review, /pr-refine, and the /issue-to-pr convergence
round. Every section comes from a command's output; nothing enters the
comment that a command did not print. The verdict and the findings stay
visible; the evidence behind them is collapsed, verbatim, so the comment
reads quickly and loses nothing.

## The protocol

- **Line 1 of the body is the marker**, exactly:
  `<!-- pr-loop-comment -->`
  Readers select round comments by this marker as the first line plus
  the author, so anything inside the body that quotes the marker string
  cannot forge a round comment.
- **Round numbering:** the first review of a PR is round 1; every refine
  round increments; the convergence round takes the next number.
- **The verdict line** is machine-read by /pr-refine. Keep it exactly one
  of:
  - `**Verdict:** No issues found.` — every source ran and produced no
    blocking finding. Follow-ups, if any, are listed below it.
  - `**Verdict:** <n> finding(s).` — <n> blocking findings, counted
    across the sources that ran. Follow-ups never count.
  - `**Verdict:** partial (the reviewer's coverage has a gap).` — the
    reviewer produced review text but left part of the range unreviewed,
    and no source produced a finding. Neither clean nor failed;
    /pr-refine has nothing to fix, and the loop cannot declare the
    branch clean off this round.
  - `**Verdict:** unrecovered (the reviewer produced no review text).` —
    the reviewer binding ended unrecovered and no other source produced
    a finding. Neither clean nor failed; /pr-refine has nothing to fix,
    and the loop cannot declare the branch clean off this round.
  - `**Verdict:** converged (all blocking findings low and dispositioned).` —
    only the orchestrator's convergence round writes this: blocking
    findings exist, every one is low, and every one is fixed, rejected,
    or accepted with a recorded reason in the Dispositions block. The
    loop ends here unless a human names a specific finding.
- **Blocking or follow-up** is pr-review's step 5: a finding blocks when
  it is high, or when `finding-scope.sh` places it on a line changed
  since the prior round's head. Every other finding is a follow-up.
- **A round over an unchanged head must address the prior verdict:**
  cite new evidence against it, or defer to it. Two comments on the
  same SHA that disagree, with nothing reconciling them, corrupt the
  record a human reads.
- **The reviewer's status is visible when it changes what the verdict
  means.** If the binding produced no review text, a line
  `**Reviewer:** unrecovered: <its message, verbatim>` sits above the
  verdict. If a run ended partial, a line `**Reviewer:** partial: <the
  failed files or the rendered warning, verbatim>` sits there instead.
  A coverage gap never lives only inside a collapsed block.

## Layout

Visible, in this order:

```markdown
<!-- pr-loop-comment -->

## Review round <N>: <short-sha>

**Reviewer:** <unrecovered: <its message, verbatim> | partial: <the failed files or the rendered warning, verbatim>>   (this line appears only when the reviewer ended unrecovered or partial; a coverage gap never lives only inside a collapsed block)

**Verdict:** <No issues found. | N finding(s). | partial (the reviewer's coverage has a gap) | unrecovered (the reviewer produced no review text) | converged (all blocking findings low and dispositioned)>

**Gate:** <command> printed <its final result>   (refine and convergence rounds only)

**Cost:** <cumulative_tokens> reviewer tokens to date, across rounds 1..N (from round.json)

**Findings:**
<N. **[reviewer|critic|read] category/severity** `file:line`: claim>   (blocking only)

**Follow-ups:**   (only when any exist)
<N. **[reviewer|critic|read] category/severity** `file:line`: claim>
```

Each finding is one line, tagged with its source: `[reviewer]` for the
reviewer binding's output, `[critic]` for the adversarial subagent,
`[read]` for the caller's own read. Number across all sources, highest
severity first, follow-ups continuing the numbering. Follow-ups are
never fixed in the loop and never dispositioned. A named finding's disposition is a record, not a
preference: fixed carries the commit and what proves it, rejected
carries the refuting evidence, accepted carries the reason a human
would give. Every disposition is one structured line in the
Dispositions block, so no later round re-litigates it.

Then, collapsed, each with blank lines inside the block (without them
GitHub renders the content as literal text):

```markdown
<details><summary>Reviewer details</summary>

<the binding renderer's output, verbatim>

</details>

<details><summary>Critic</summary>

<the critic subagent's findings, verbatim>

</details>

<details><summary>Caller's read</summary>

<the caller's own findings, verbatim; "No findings." is a valid entry>

</details>

<details><summary>Dispositions</summary>   (whenever a named finding was fixed, rejected, or accepted; never silently dropped)

- Fixed: [reviewer|critic|read] <finding, one line> — in <short-sha>, <the test or gate result that proves it>
- Rejected: [reviewer|critic|read] <finding, one line> — <the reason, with the evidence>
- Accepted: [reviewer|critic|read] <finding, one line> — <the reason>

</details>

*Round <N> | <short-sha> | reviewer <binding> | critic <binding>*
```

The renderer escapes `</details>` in its output; the critic's and the
read's text pass through the same scan, so quote them inside fenced
blocks when they contain markup.

## Scan before posting

```bash
~/.claude/skills/issue-to-pr/tools/scan.sh <file>
```

The script replaces home-directory paths with `~` in place. Exit 1
means a hit remains (another home path, a temp path, a token): do not
post; record the printed lines and surface them in the loop's final
report. In an interactive round, show the lines and wait instead.
