# The issue-to-PR loop: flow

One picture of the unattended loop that /issue-to-pr drives and
/pr-review and /pr-refine serve. The skills are the contract; this
diagram is the map. When the two disagree, the skills win and this file
gets fixed.

**Verdict states** (machine-read by the next round):

- `No issues found.` — every source ran and produced no blocking
  finding.
- `<n> finding(s).` — blocking findings exist, counted across the
  sources that ran. A finding blocks when it is high or sits on a line
  changed since the prior round's head; the rest are follow-ups for the
  human, never refine work.
- `partial (the reviewer's coverage has a gap)` — review text exists but
  part of the range went unreviewed; neither clean nor failing; the
  loop cannot declare the branch clean off that round.
- `unrecovered (the reviewer produced no review text)` — neither clean
  nor failing; the loop cannot declare the branch clean off that round.
- `converged (all blocking findings low and dispositioned)` — the
  orchestrator's convergence round only: blocking findings existed,
  every one low and fixed,
  rejected, or accepted with a recorded reason. The loop ends unless a
  human names a finding.

**Loop end states** (the final message, the runner's contract): `clean`,
`converged` (all blocking findings low and dispositioned; accepted
judgment calls listed), `capped-unrecovered` (blocking findings remain
after 3 refine rounds),
`blocked` (pane death after redispatch, no gate, scan hit, or a partial
or unrecovered reviewer with nothing from any source).

## The loop

```mermaid
flowchart TD
    A["Intake: a task ref<br/>gh issue, markdown todo, or HTML file<br/>confirm brief, layout, gate, reviewer, grill"] --> B{"Open PR with head<br/>branch-name already?"}
    B -- "yes: resume" --> R
    B -- "no" --> C["Dispatch<br/>workmux add branch-name -b -l layout -P prompt-file<br/>verify the pane binary with tmux list-panes"]
    C --> G1{"Grill on?"}
    G1 -- "yes" --> G2["In the pane: plan, grill-me with the human,<br/>restate decisions, get a yes<br/>(the pane waits on the human; not pane death)"]
    G2 --> D
    G1 -- "no" --> D
    D["Implementer pane<br/>TDD, gate, conventional commits,<br/>push, gh pr create with Closes for gh issues"]
    D --> E{"PR verified and bound<br/>to branch-name?"}
    E -- "no: a real number, someone else's PR" --> X["Blocked: report and stop"]
    E -- "yes" --> R["Review round<br/>pr-round.sh: range resolved from the PR,<br/>identity check, reviewer binding,<br/>per-commit empty-retry"]
    R --> F["Adversarial critic: fresh clean-context subagent<br/>plus the caller's own read"]
    F --> FS["finding-scope.sh per finding:<br/>high or on the delta blocks,<br/>the rest are follow-ups"]
    FS --> G["Assemble the comment per report-template<br/>marker first line, five-state verdict"]
    G --> S{"Scan before posting"}
    S -- "hit: do not leak" --> Y["Abort the post, record it,<br/>the final report surfaces it"]
    S -- "clean" --> H["Post the round comment<br/>append per round"]
    H --> I{"Verdict"}
    I -- "No issues found" --> J["Convergence<br/>the orchestrator runs pr-round.sh itself<br/>and gates in the implementer worktree,<br/>after rev-parse HEAD equals headRefOid"]
    I -- "blocking findings" --> K{"Refine rounds<br/>under the cap of 3?"}
    K -- "yes" --> L["workmux send: run pr-refine<br/>named blocking findings only, one re-run,<br/>validate, value brake, severity gates,<br/>TDD fix, gate, commit, push"]
    L --> RC{"All blocking findings low<br/>and all dispositioned?"}
    RC -- "yes: converged candidate" --> J
    RC -- "no" --> R
    I -- "partial or unrecovered" --> P["Neither clean nor failing;<br/>nothing to fix, no clean claim"]
    K -- "no" --> M["Capped-unrecovered:<br/>findings remain after 3 rounds"]
    J --> N{"Convergence round clean<br/>and the gate green?"}
    N -- "yes" --> O["Clean: the loop ends"]
    N -- "no" --> K
    X --> Z["Final message: the report"]
    Y --> Z
    P --> Z
    M --> Z
    O --> Z
```

## The tool slots

The process is fixed; the tools are bindings. A swap is one directory
plus one manifest line, never a skill edit.

```mermaid
flowchart LR
    S["pr-review, pr-refine,<br/>and convergence"] --> P["tools/pr-round.sh<br/>range, identity, empty-retry,<br/>round.json"]
    P --> M["tools/manifest.json<br/>reviewer: ocr<br/>critic: subagent"]
    S --> FS["tools/finding-scope.sh<br/>blocking or follow-up<br/>against the round's delta.txt"]
    M --> R["tools/ocr<br/>review.sh runs the tool<br/>render.sh renders its output"]
    M --> C["tools/subagent<br/>binding.md: how to spawn<br/>critic-prompt.md: what it attacks<br/>critic-input.sh: the verbatim prompt"]
    P --> O["round dir under<br/>HOME/.cache/pr-loop:<br/>review.json per run,<br/>round.json for the round,<br/>delta.txt and names.txt<br/>from round 2 on, except after<br/>a rebase or without a usable<br/>prior head; empty delta.txt<br/>when nothing changed<br/>since the prior head"]
    S --> SC["tools/scan.sh<br/>the leak gate every round<br/>comment passes before posting"]
    S --> BN["tools/branch-name.sh<br/>deterministic loop branch names<br/>for intake and resume"]
```

## Where things live

| Thing | Path |
|---|---|
| Orchestrator skill | `~/.claude/skills/issue-to-pr/SKILL.md` |
| Review round skill | `~/.claude/skills/pr-review/SKILL.md` |
| Refine round skill | `~/.claude/skills/pr-refine/SKILL.md` |
| Report template | `~/.claude/skills/pr-review/report-template.md` |
| Implementer prompt | `~/.claude/skills/issue-to-pr/dispatch-prompt-template.md` |
| Slot manifest and bindings | `~/.claude/skills/issue-to-pr/tools/` |
| Leak gate | `~/.claude/skills/issue-to-pr/tools/scan.sh` |
| Branch-name tool | `~/.claude/skills/issue-to-pr/tools/branch-name.sh` |
| Finding classifier | `~/.claude/skills/issue-to-pr/tools/finding-scope.sh` |
| Critic prompt builder | `~/.claude/skills/issue-to-pr/tools/subagent/critic-input.sh` |
| Round artifacts | `$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/round-<N>/` |
| Final report | `$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/final-report.md` |
| workmux layouts | `~/.config/workmux/config.yaml` (chezmoi: `dot_config/workmux/config.yaml`) |
| opencode stack agents | `~/.config/opencode/agent/sp.md`, `mp.md` (not chezmoi-managed yet) |
