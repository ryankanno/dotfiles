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
  - `**Verdict:** No issues found.` — every source ran and produced zero
    findings.
  - `**Verdict:** <n> finding(s).` — findings exist, counted across the
    sources that ran.
  - `**Verdict:** unrecovered (the reviewer produced no review text).` —
    the reviewer binding ended unrecovered and no other source produced
    a finding. Neither clean nor failed; /pr-refine has nothing to fix,
    and the loop cannot declare the branch clean off this round.
  - `**Verdict:** converged (all findings low and dispositioned).` —
    only the orchestrator's convergence round writes this: findings
    exist, every one is low, and every one is fixed, rejected, or
    accepted with a recorded reason in the Dispositions block. The loop
    ends here unless a human names a specific finding.
- **A round over an unchanged head must address the prior verdict:**
  cite new evidence against it, or defer to it. Two comments on the
  same SHA that disagree, with nothing reconciling them, corrupt the
  record a human reads.
- **The reviewer's status is visible when it changes what the verdict
  means.** If the binding produced no review text, a line
  `**Reviewer:** unrecovered: <its message, verbatim>` sits above the
  verdict. A coverage gap never lives only inside a collapsed block.

## Layout

Visible, in this order:

```markdown
<!-- pr-loop-comment -->

## Review round <N>: <short-sha>

**Reviewer:** <unrecovered: <its message, verbatim> |  (this line appears only when the reviewer produced no review text; a coverage gap never lives only inside a collapsed block)>

**Verdict:** <No issues found. | N finding(s). | unrecovered (the reviewer produced no review text) | converged (all findings low and dispositioned)>

**Gate:** <command> printed <its final result>   (refine and convergence rounds only)

**Cost:** <cumulative_tokens> reviewer tokens to date, across rounds 1..N (from round.json)

**Findings:**
<N. **[reviewer|critic|read] category/severity** `file:line`: claim>
```

Each finding is one line, tagged with its source: `[reviewer]` for the
reviewer binding's output, `[critic]` for the adversarial subagent,
`[read]` for the caller's own read. Number across all sources, highest
severity first. A named finding's disposition is a record, not a
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
grep -nE "$HOME|$USER|/Users/|/home/|/private/|/var/folders/|127\.0\.0\.1|localhost|(sk|ghp|gho|ghu|ghs|ghr|github_pat)[-_][A-Za-z0-9_]{10,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|glpat-[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|[Bb]earer " <file>
```

Replace a home-directory path with `~`. Anything else it finds (a temp
path, a local URL, a token): do not post; record the line and surface it
in the loop's final report. In an interactive round, show the lines and
wait instead.
