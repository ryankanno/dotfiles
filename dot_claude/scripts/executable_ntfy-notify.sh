#!/usr/bin/env bash
# Send Claude Code hook events to an ntfy server.
#
# Usage:
#   ntfy-notify.sh notification            # generic; reads hook JSON from stdin
#   ntfy-notify.sh notification-idle       # Claude is idle waiting
#   ntfy-notify.sh notification-permission # Claude needs a permission decision
#   ntfy-notify.sh stop                    # task-completion for current repo
#   ntfy-notify.sh subagent-stop           # subagent-completion
#
# Silently exits 0 if NTFY_SERVER_URL is unset.

set -euo pipefail

mode="${1:-}"

if [ -z "${NTFY_SERVER_URL:-}" ]; then
    exit 0
fi

topic="${NTFY_TOPIC:-cc}"
url="${NTFY_SERVER_URL%/}/${topic}"

post() {
    local title="$1"
    local body="$2"
    local priority="${3:-3}"
    curl -s --max-time 5 \
        -H "Title: ${title}" \
        -H "Priority: ${priority}" \
        -d "${body}" \
        "${url}" >/dev/null || true
}

repo_info() {
    local remote branch
    remote=$(git remote get-url origin 2>/dev/null || true)
    branch=$(git branch --show-current 2>/dev/null || echo "no git")
    if [ -n "${remote}" ]; then
        remote=$(echo "${remote}" | sed 's|.*[/:]\([^/]*/[^/]*\)$|\1|; s|\.git$||')
    else
        remote="unknown"
    fi
    printf '%s\t%s' "${remote}" "${branch}"
}

read_notification() {
    payload=$(cat)
    title=$(echo "${payload}" | jq -r '.title // "Claude Code"')
    message=$(echo "${payload}" | jq -r '.message // "No message"')
}

case "${mode}" in
    notification)
        read_notification
        post "${title}" "${message}"
        ;;
    notification-idle)
        read_notification
        post "Claude Code (idle)" "${message}" 3
        ;;
    notification-permission)
        read_notification
        post "Claude Code (needs permission)" "${message}" 4
        ;;
    stop)
        IFS=$'\t' read -r repo branch < <(repo_info)
        post "Claude Code" "Task completed for ${repo} ($(pwd)) on branch ${branch} 🎆"
        ;;
    subagent-stop)
        IFS=$'\t' read -r repo branch < <(repo_info)
        post "Claude Code: Subagent" "Subagent done in ${repo} on branch ${branch}"
        ;;
    *)
        echo "usage: $0 {notification|notification-idle|notification-permission|stop|subagent-stop}" >&2
        exit 2
        ;;
esac
