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
# Topics are <os>-<NTFY_TOPIC> (default <os>-cc); priority 4+ events route to <os>-<NTFY_TOPIC>-high.
# Silently exits 0 if NTFY_SERVER_URL is unset.

set -euo pipefail

mode="${1:-}"

if [ -z "${NTFY_SERVER_URL:-}" ]; then
    exit 0
fi

# Group hosts by OS so each class gets its own ntfy topic; WSL counts as windows.
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Linux)
            if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
                echo "windows"
            else
                echo "linux"
            fi
            ;;
        *) uname -s | tr '[:upper:]' '[:lower:]' ;;
    esac
}

topic_base="$(detect_os)-${NTFY_TOPIC:-cc}"
base_url="${NTFY_SERVER_URL%/}"

post() {
    local title="$1"
    local body="$2"
    local priority="${3:-3}"
    local tags="${4:-}"
    # Priority 4+ gets its own topic; the ntfy Android app filters per-topic, not per-message.
    local topic="${topic_base}"
    if [ "${priority}" -ge 4 ]; then
        topic="${topic_base}-high"
    fi
    curl -s --max-time 5 \
        -H "Content-Type: application/json" \
        -d "$(jq -nc \
            --arg topic "${topic}" \
            --arg title "${title}" \
            --arg message "${body}" \
            --argjson priority "${priority}" \
            --arg tags "${tags}" \
            '{topic: $topic, title: $title, message: $message, priority: $priority, tags: ($tags | split(","))}' \
        )" \
        "${base_url}" >/dev/null || true
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
    printf '%s\t%s\n' "${remote}" "${branch}"
}

read_notification() {
    if [ -t 0 ]; then
        payload='{}'
    else
        payload=$(cat)
    fi
    title=$(echo "${payload}" | jq -r '.title // "Claude Code"')
    message=$(echo "${payload}" | jq -r '.message // "No message"')
}

location() {
    IFS=$'\t' read -r repo branch < <(repo_info)
    printf '[%s @ %s — %s]' "${repo}" "${branch}" "$(pwd)"
}

case "${mode}" in
    notification)
        read_notification
        post "${title}" "${message} $(location)" 3 "speech_balloon"
        ;;
    notification-idle)
        read_notification
        post "Claude Code (idle)" "${message} $(location)" 4 "hourglass_flowing_sand"
        ;;
    notification-permission)
        read_notification
        post "Claude Code (needs permission)" "${message} $(location)" 4 "lock"
        ;;
    stop)
        post "Claude Code" "Task completed $(location)" 4 "tada"
        ;;
    subagent-stop)
        post "Claude Code: Subagent" "Subagent done $(location)" 4 "robot"
        ;;
    *)
        echo "usage: $0 {notification|notification-idle|notification-permission|stop|subagent-stop}" >&2
        exit 2
        ;;
esac
