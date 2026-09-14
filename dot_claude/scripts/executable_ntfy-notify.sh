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
# Topics are <os>-<source> (cc for Claude Code hooks, roborev for roborev);
# priority 4+ events route to <os>-<source>-high. NTFY_TOPIC overrides <source>.
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

# Each source gets its own topic so a subscriber can label, icon, and mute
# them separately. Sharing one topic meant every message rendered under
# whichever app name that topic's command happened to hardcode.
case "${mode}" in
    roborev) source_topic="roborev" ;;
    *) source_topic="cc" ;;
esac

topic_base="$(detect_os)-${NTFY_TOPIC:-${source_topic}}"
base_url="${NTFY_SERVER_URL%/}"

post() {
    local title="$1"
    local body="$2"
    local priority="${3:-3}"
    local tags="${4:-}"
    local click="${5:-}"
    local topic="${topic_base}"
    if [ "${priority}" -ge 4 ]; then
        topic="${topic_base}-high"
    fi
    local jq_args=(
        --arg topic "${topic}"
        --arg title "${title}"
        --arg message "${body}"
        --argjson priority "${priority}"
        --arg tags "${tags}"
    )
    local jq_filter='{topic: $topic, title: $title, message: $message, priority: $priority, tags: ($tags | split(","))}'
    if [ -n "${click}" ]; then
        jq_args+=(--arg click "${click}")
        jq_filter='{topic: $topic, title: $title, message: $message, priority: $priority, tags: ($tags | split(",")), click: $click}'
    fi
    curl -s --max-time 5 \
        -H "Content-Type: application/json" \
        -d "$(jq -nc "${jq_args[@]}" "${jq_filter}")" \
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

repo_label() {
    local repo branch
    IFS=$'\t' read -r repo branch < <(repo_info)
    printf '%s@%s' "${repo}" "${branch}"
}

pwd_line() {
    printf '📂 %s' "$(pwd)"
}

tmux_click_url() {
    if [ -z "${TMUX_PANE:-}" ]; then
        return
    fi
    local s w p
    s=$(tmux display-message -p -t "${TMUX_PANE}" '#S' 2>/dev/null) || return
    w=$(tmux display-message -p -t "${TMUX_PANE}" '#I' 2>/dev/null) || return
    p=$(tmux display-message -p -t "${TMUX_PANE}" '#P' 2>/dev/null) || return
    printf 'tmux-focus://switch?session=%s&window=%s&pane=%s' "${s}" "${w}" "${p}"
}

case "${mode}" in
    notification)
        read_notification
        post "💬 ${title}: $(repo_label)" "${message}"$'\n'"$(pwd_line)" 3 "speech_balloon,bell" "$(tmux_click_url)"
        ;;
    notification-idle)
        read_notification
        post "⏳ Idle: $(repo_label)" "${message}"$'\n'"$(pwd_line)" 4 "hourglass_flowing_sand,zzz" "$(tmux_click_url)"
        ;;
    notification-permission)
        read_notification
        post "🔐 Permission needed: $(repo_label)" "${message}"$'\n'"$(pwd_line)" 4 "lock,rotating_light" "$(tmux_click_url)"
        ;;
    stop)
        post "✅ Done: $(repo_label)" "Task complete"$'\n'"$(pwd_line)" 4 "white_check_mark,tada" "$(tmux_click_url)"
        ;;
    subagent-stop)
        post "🤖 Subagent done: $(repo_label)" "Subagent finished"$'\n'"$(pwd_line)" 4 "robot,checkered_flag" "$(tmux_click_url)"
        ;;
    roborev)
        # args: repo_name repo_path sha verdict detail
        # verdict P=pass, F=findings, anything else=job error
        shift
        rr_repo="${1:-unknown}"
        rr_path="${2:-}"
        rr_sha="${3:-}"
        rr_verdict="${4:-}"
        rr_detail="${5:-}"

        # Best-effort GitHub link: the PR containing the head commit, else the
        # commit page. A slow or failed lookup must never delay the notification.
        rr_click=""
        rr_head="${rr_sha##*..}"
        if [ -d "${rr_path}" ] && [ -n "${rr_head}" ]; then
            rr_slug=$(git -C "${rr_path}" remote get-url origin 2>/dev/null \
                | sed 's|.*[/:]\([^/]*/[^/]*\)$|\1|; s|\.git$||') || rr_slug=""
            if [ -n "${rr_slug}" ]; then
                rr_click=$(timeout 5 gh api "repos/${rr_slug}/commits/${rr_head}/pulls" \
                    --jq '.[0].html_url // empty' 2>/dev/null) || rr_click=""
                if [ -z "${rr_click}" ]; then
                    rr_click="https://github.com/${rr_slug}/commit/${rr_head}"
                fi
            fi
        fi

        case "${rr_verdict}" in
            P)
                post "✅ roborev pass: ${rr_repo}" "${rr_head}" 3 "white_check_mark" "${rr_click}"
                ;;
            F)
                post "❌ roborev findings: ${rr_repo}" "${rr_head}"$'\n'"${rr_detail}" 4 "x,mag" "${rr_click}"
                ;;
            *)
                post "💥 roborev error: ${rr_repo}" "${rr_head}"$'\n'"${rr_detail}" 4 "boom,rotating_light" "${rr_click}"
                ;;
        esac
        ;;
    *)
        echo "usage: $0 {notification|notification-idle|notification-permission|stop|subagent-stop|roborev}" >&2
        exit 2
        ;;
esac
