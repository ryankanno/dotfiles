# The issue-to-PR loop: flow

One picture of the unattended loop that /issue-to-pr drives and
/pr-review and /pr-refine serve. The skills are the contract; this
diagram is the map. When the two disagree, the skills win and this file
gets fixed.

**Verdict states** (machine-read by the next round): the verdict list
in [`report-template.md`](../pr-review/report-template.md).

**Ownership:** the implementer pane runs every round (round 1, refine,
convergence). The orchestrator runs none; it ratifies.

**Loop end states** (the final message, the runner's contract): `clean`,
`converged`, `capped-unrecovered` or `blocked`, as issue-to-pr §7
([`SKILL.md`](SKILL.md)) defines each.

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
    D["Implementer pane<br/>TDD, gate, conventional commits,<br/>push, gh pr create --draft with Closes for gh issues"]
    D --> E{"PR verified and bound<br/>to branch-name?"}
    E -- "no: a real number, someone else's PR" --> X["Blocked: report and stop"]
    E -- "yes" --> R["Review round, run by the pane<br/>pr-round.sh: range resolved from the PR,<br/>identity check, reviewer binding,<br/>per-commit empty-retry"]
    R --> F["Adversarial critic: fresh clean-context subagent<br/>plus the caller's own read"]
    F --> FS["finding-scope.sh per finding:<br/>high or on the delta blocks,<br/>the rest are follow-ups"]
    FS --> G["Assemble the comment per report-template<br/>marker first line, the verdict"]
    G --> S{"Scan before posting"}
    S -- "hit: do not leak" --> Y["Abort the post, record it,<br/>the final report surfaces it"]
    S -- "clean" --> H["Post the round comment<br/>append per round"]
    H --> I{"Verdict"}
    I -- "No issues found, round 1" --> N
    I -- "No issues found, after a refine" --> J["Convergence round, run by the pane<br/>pr-round.sh --convergence on the same head:<br/>the whole PR from the merge base"]
    I -- "blocking findings" --> K{"Refine rounds<br/>under the cap of 3?"}
    K -- "yes" --> L["The pane runs pr-refine<br/>named blocking findings only, one re-run,<br/>validate, value brake, severity gates,<br/>TDD fix, gate, commit, push"]
    L --> RC{"All blocking findings low<br/>and all dispositioned?"}
    RC -- "yes: converged candidate" --> J
    RC -- "no" --> R
    I -- "partial, nothing reviewable,<br/>or unrecovered" --> P["Neither clean nor failing;<br/>nothing to fix, no clean claim"]
    K -- "no" --> M["Capped-unrecovered:<br/>findings remain after 3 refine rounds"]
    J --> JB{"Convergence round blocking?"}
    JB -- "yes" --> K
    JB -- "no: the pane stops" --> N{"Orchestrator ratifies:<br/>round.json head = headRefOid,<br/>review_scope full, comment posted<br/>(or a scanned draft, not owned),<br/>gate green in the worktree,<br/>every Rejected/Accepted holds,<br/>its own read of the diff holds"}
    N -- "yes" --> O["Clean or converged: gh pr ready if a draft,<br/>the loop ends"]
    N -- "a disposition or the read fails" --> K
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
    P --> O["round dir under<br/>HOME/.cache/pr-loop:<br/>review.json per run,<br/>round.json for the round,<br/>delta.txt and names.txt<br/>from round 2 on, except after<br/>a rebase, without a usable<br/>prior head, or when the change<br/>adds or modifies no lines;<br/>empty delta.txt when the<br/>tree did not change"]
    S --> SC["tools/scan.sh<br/>the leak gate every round<br/>comment passes before posting"]
    S --> BN["tools/branch-name.sh<br/>deterministic loop branch names<br/>for intake and resume"]
```

## Where things live

| Thing | Path |
|---|---|
| Orchestrator skill | `$HOME/.claude/skills/issue-to-pr/SKILL.md` |
| Review round skill | `$HOME/.claude/skills/pr-review/SKILL.md` |
| Refine round skill | `$HOME/.claude/skills/pr-refine/SKILL.md` |
| Report template | `$HOME/.claude/skills/pr-review/report-template.md` |
| Implementer prompt | `$HOME/.claude/skills/issue-to-pr/dispatch-prompt-template.md` |
| Slot manifest and bindings | `$HOME/.claude/skills/issue-to-pr/tools/` |
| Leak gate | `$HOME/.claude/skills/issue-to-pr/tools/scan.sh` |
| Branch-name tool | `$HOME/.claude/skills/issue-to-pr/tools/branch-name.sh` |
| Round comment (read before the PR copy) | `$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/round-<N>/comment.md` |
| Finding classifier | `$HOME/.claude/skills/issue-to-pr/tools/finding-scope.sh` |
| Critic prompt builder | `$HOME/.claude/skills/issue-to-pr/tools/subagent/critic-input.sh` |
| Round artifacts | `$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/round-<N>/` |
| Final report | `$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/final-report.md` |
| workmux layouts | `~/.config/workmux/config.yaml` (chezmoi: `dot_config/workmux/config.yaml`) |
| opencode stack agents | `~/.config/opencode/agent/sp.md`, `mp.md` (not chezmoi-managed yet) |
