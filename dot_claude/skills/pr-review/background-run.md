# A round in a detached tmux session

pr-review §1 links here for a harness with no background run that
outlives the tool call's time limit (opencode's bash tool stops a call
after 120 seconds by default). Create the PR's round folder first, as
pr-review §1 says.

A tmux session survives the end of the tool call; a background
`&` job of the call can die with it. A tmux session gets the tmux
server's environment, not yours (a PATH without `gh` exits 127), so
pass your PATH:

```bash
tmux new-session -d -e PATH="$PATH" \
  -e LOG="$HOME/.cache/pr-loop/<owner/repo>/pr-<n>/round-<N>.log" \
  -s pr-round-<n>-<N> sh -c \
  '$HOME/.claude/skills/issue-to-pr/tools/pr-round.sh <args> >"$LOG" 2>&1; echo "exit=$?" >>"$LOG"'
```

Then poll. Each poll is one tool call with a sleep shorter than the
tool's limit (`sleep 100` under opencode's default).
