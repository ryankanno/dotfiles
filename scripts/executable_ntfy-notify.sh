#!/usr/bin/env bash
# Called by `ntfy subscribe TOPIC HELPER` once per message. Bridges the
# message to macOS Notification Center.
#
# Uses `alerter` (brew install alerter) when available so the notification
# can be clicked to open the message's Click URL and stays sticky until
# dismissed. Falls back to `osascript` otherwise.
#
# Env vars provided by ntfy CLI:
#   $NTFY_TIME, $NTFY_TITLE, $NTFY_MESSAGE, $NTFY_PRIORITY (1=min..5=max),
#   $NTFY_RAW (full JSON; source of .click since there is no $NTFY_CLICK).
set -u

title="${NTFY_TITLE:-ntfy}"
message="${NTFY_MESSAGE:-}"
priority="${NTFY_PRIORITY:-3}"
raw="${NTFY_RAW:-}"

click_url=""
if [[ -n "$raw" ]] && command -v jq >/dev/null 2>&1; then
    click_url=$(printf '%s' "$raw" | jq -r '.click // ""' 2>/dev/null || true)
fi

log_file="$HOME/Library/Logs/ntfy-notify.log"
mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$log_file"; }
log "title=$title priority=$priority click_url=${click_url:-<none>}"
log "raw=$raw"

alerter_bin=$(command -v alerter || true)

if [[ -n "$alerter_bin" ]]; then
    sound_args=()
    timeout=30
    if [[ "$priority" =~ ^[0-9]+$ ]] && (( priority >= 4 )); then
        sound_args=(--sound Glass)
        timeout=120
    fi

    # Rotate group IDs across N slots so Notification Center keeps the
    # most recent N alerts. Single group would collapse to one; no group
    # would stack unbounded.
    stack_size="${NTFY_STACK_SIZE:-5}"
    # Reject empty, non-numeric, or zero values to avoid arithmetic errors.
    [[ ! "$stack_size" =~ ^[1-9][0-9]*$ ]] && stack_size=5
    state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/ntfy-notify"
    mkdir -p "$state_dir" 2>/dev/null || true
    counter_file="$state_dir/group-counter"
    counter=0
    if [[ -f "$counter_file" ]]; then
        counter=$(cat "$counter_file" 2>/dev/null || echo 0)
        [[ ! "$counter" =~ ^[0-9]+$ ]] && counter=0
    fi
    group_idx=$(( counter % stack_size ))
    printf '%s' "$(( (counter + 1) % 1000000 ))" > "$counter_file" 2>/dev/null || true
    group_id="claude-code-${group_idx}"

    # Run alerter in background so the ntfy subscribe helper returns
    # immediately. --timeout caps how long the alert sits in Notification
    # Center; on click (contentsClicked) open the Click URL.
    (
        result=$("$alerter_bin" \
            --title "$title" \
            --message "$message" \
            --timeout "$timeout" \
            --group "$group_id" \
            --json \
            "${sound_args[@]}" 2>/dev/null || true)
        log "alerter_result=$result"
        if [[ -n "$click_url" ]] && command -v jq >/dev/null 2>&1; then
            atype=$(printf '%s' "$result" | jq -r '.activationType // ""' 2>/dev/null || true)
            avalue=$(printf '%s' "$result" | jq -r '.activationValue // ""' 2>/dev/null || true)
            log "activationType=$atype activationValue=$avalue"
            # contentsClicked = tap on banner body (older macOS).
            # actionClicked with empty value = same tap on macOS 13+ via alerter.
            if [[ "$atype" == "contentsClicked" ]] || \
               { [[ "$atype" == "actionClicked" ]] && [[ -z "$avalue" ]]; }; then
                log "opening $click_url"
                /usr/bin/open "$click_url" >/dev/null 2>&1 || true
            fi
        fi
    ) &
    exit 0
fi

# Fallback: native osascript. No click support, no group/replace, no
# timeout control (dwell controlled by System Settings -> Notifications
# -> Script Editor: Alert vs Banner). Install `alerter` for full features.
#
# Whitespace conversion: AppleScript string literals accept \n \r \t as
# escapes. Sender embeds real newlines via $'\n'; pass them through as
# literal escapes so AppleScript renders line breaks instead of breaking
# the source.
title_esc=${title//\\/\\\\}
title_esc=${title_esc//\"/\\\"}
title_esc=${title_esc//$'\n'/\\n}
title_esc=${title_esc//$'\r'/\\r}
title_esc=${title_esc//$'\t'/\\t}
message_esc=${message//\\/\\\\}
message_esc=${message_esc//\"/\\\"}
message_esc=${message_esc//$'\n'/\\n}
message_esc=${message_esc//$'\r'/\\r}
message_esc=${message_esc//$'\t'/\\t}

sound=""
if [[ "$priority" =~ ^[0-9]+$ ]] && (( priority >= 4 )); then
    sound=' sound name "Glass"'
fi

/usr/bin/osascript -e "display notification \"$message_esc\" with title \"$title_esc\"$sound" || true
