#!/usr/bin/env bash
set -euo pipefail

RUNNER_VERSION="${RUNNER_VERSION:-2.334.0}"

# Default the runner arch to this host's OS/CPU so `add` works out of the box on
# both macOS and Linux. RUNNER_ARCH still overrides (e.g. cross-arch runners).
default_arch() {
  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64) echo osx-arm64 ;;
    Darwin/x86_64) echo osx-x64 ;;
    Linux/x86_64) echo linux-x64 ;;
    Linux/aarch64 | Linux/arm64) echo linux-arm64 ;;
    *) echo osx-arm64 ;;
  esac
}
RUNNER_ARCH="${RUNNER_ARCH:-$(default_arch)}"

BASE_DIR="${GITHUB_RUNNERS_DIR:-$HOME/.github-action-runners}"
CACHE_DIR="$BASE_DIR/.cache"
TARBALL="actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

die() { echo "error: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
usage:
  runner.sh add <owner> [repo] [--labels a,b,c] [--name <name>]
  runner.sh remove <folder-name>
  runner.sh list <owner> [repo]
  runner.sh restart
EOF
  exit 1
}

# Echoes orgs/<owner> for an Organization, repos/<owner>/<repo> for a repo.
# Errors if a personal account is given without a repo.
resolve_target() {
  local owner="$1" repo="$2"
  if [[ -n "$repo" ]]; then
    echo "repos/$owner/$repo"
    return 0
  fi
  local otype
  otype="$(owner_type "$owner")"
  [[ "$otype" == "Organization" ]] \
    || die "$owner is a $otype; personal accounts work per repo. Pass: $owner <repo>"
  echo "orgs/$owner"
}

require_deps() {
  command -v gh >/dev/null 2>&1 || die "gh CLI not found. brew install gh"
  command -v jq >/dev/null 2>&1 || die "jq not found. brew install jq"
  gh auth status >/dev/null 2>&1 || die "gh not authenticated. Run: gh auth login"
}

# Populate the tarball cache: copy a seed if RUNNER_TARBALL_SEED points at one,
# otherwise download from the actions/runner releases.
ensure_tarball() {
  mkdir -p "$CACHE_DIR"
  local dest="$CACHE_DIR/$TARBALL"
  [[ -f "$dest" ]] && return 0
  local seed="${RUNNER_TARBALL_SEED:-}"
  if [[ -n "$seed" && -f "$seed" ]]; then
    cp "$seed" "$dest"
    return 0
  fi
  echo "Downloading $TARBALL ..."
  gh release download "v${RUNNER_VERSION}" \
    --repo actions/runner \
    --pattern "$TARBALL" \
    --dir "$CACHE_DIR" \
    || die "failed to download $TARBALL"
}

# Echoes "User" or "Organization".
owner_type() { gh api "/users/$1" --jq .type; }

# Maps https://github.com/<owner>[/<repo>] to orgs/<owner> or repos/<owner>/<repo>.
api_target_from_url() {
  local path="${1#https://github.com/}"
  path="${path%/}"
  if [[ "$path" == */* ]]; then
    echo "repos/$path"
  else
    echo "orgs/$path"
  fi
}

cmd_add() {
  local labels="" name_override=""
  local -a positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --labels) labels="$2"; shift 2;;
      --name)   name_override="$2"; shift 2;;
      -h|--help) usage;;
      -*) die "unknown flag: $1";;
      *) positional+=("$1"); shift;;
    esac
  done
  set -- "${positional[@]:-}"
  local owner="${1:-}" repo="${2:-}"
  [[ -n "$owner" ]] || usage

  require_deps

  local target url folder
  if [[ -n "$repo" ]]; then
    target="repos/$owner/$repo"
    url="https://github.com/$owner/$repo"
    folder="actions-runner-$owner-$repo"
  else
    local otype
    otype="$(owner_type "$owner")"
    [[ "$otype" == "Organization" ]] \
      || die "$owner is a $otype; personal accounts need a repo. Run: runner.sh add $owner <repo>"
    target="orgs/$owner"
    url="https://github.com/$owner"
    folder="actions-runner-$owner"
  fi

  # A repo/org can host several runners. If the folder is taken, append the
  # next free -N suffix so the folder (and thus the runner name) stays unique.
  local dir="$BASE_DIR/$folder"
  if [[ -e "$dir" ]]; then
    local n=1
    while [[ -e "$BASE_DIR/$folder-$n" ]]; do n=$((n+1)); done
    folder="$folder-$n"
    dir="$BASE_DIR/$folder"
  fi

  local name="${name_override:-$folder}"

  ensure_tarball
  mkdir -p "$dir"
  tar -xzf "$CACHE_DIR/$TARBALL" -C "$dir"

  echo "Requesting registration token for $target ..."
  local token
  token="$(gh api -X POST "/$target/actions/runners/registration-token" --jq .token)"
  [[ -n "$token" ]] || die "failed to get registration token"

  (
    cd "$dir"
    local -a args=(--unattended --replace --url "$url" --token "$token" --name "$name" --work _work)
    [[ -n "$labels" ]] && args+=(--labels "$labels")
    ./config.sh "${args[@]}"
    # svc.sh manages a launchd agent on macOS (no sudo) but a systemd service on
    # Linux (needs root, and the user to run the service as).
    if [[ "$(uname -s)" == "Linux" ]]; then
      sudo ./svc.sh install "$(whoami)"
      sudo ./svc.sh start
    else
      ./svc.sh install
      ./svc.sh start
    fi
  )

  echo "Runner '$name' registered at $url; service started."
  echo "Verify: gh api /$target/actions/runners --jq '.runners[].name'"
}

cmd_remove() {
  local folder="${1:-}"
  [[ -n "$folder" ]] || usage

  require_deps

  local dir="$BASE_DIR/$folder"
  [[ -d "$dir" ]] || die "$dir not found"

  local runner_file="$dir/.runner"
  if [[ ! -f "$runner_file" ]]; then
    {
      echo "warning: $runner_file missing; folder looks half-built."
      echo "Deleting folder only. A GitHub-side runner may linger; list with:"
      echo "  gh api /<orgs|repos>/<owner>[/<repo>]/actions/runners"
    } >&2
    rm -rf "$dir"
    echo "Deleted $dir"
    return 0
  fi

  local url agent_id name target
  url="$(jq -r .gitHubUrl "$runner_file")"
  agent_id="$(jq -r .agentId "$runner_file")"
  name="$(jq -r .agentName "$runner_file")"
  target="$(api_target_from_url "$url")"

  (
    cd "$dir"
    # Service may not be installed; tolerate failure either way. Linux svc.sh
    # (systemd) needs root, matching the sudo used at install time.
    if [[ "$(uname -s)" == "Linux" ]]; then
      sudo ./svc.sh stop      || true
      sudo ./svc.sh uninstall || true
    else
      ./svc.sh stop      || true
      ./svc.sh uninstall || true
    fi
  )

  echo "Deregistering runner $name (id $agent_id) from $target ..."
  gh api -X DELETE "/$target/actions/runners/$agent_id" \
    || echo "warning: GitHub deregister failed (already gone?); continuing." >&2

  rm -rf "$dir"
  echo "Removed runner '$name'; deleted $dir"
}

cmd_list() {
  local owner="${1:-}" repo="${2:-}"
  [[ -n "$owner" ]] || usage

  require_deps

  local target
  target="$(resolve_target "$owner" "$repo")"

  printf 'NAME\tSTATUS\tBUSY\tLABELS\n'
  gh api "/$target/actions/runners" --paginate \
    --jq '.runners[] | [.name, .status, (.busy|tostring), (.labels|map(.name)|join(","))] | @tsv'
}

# Restart every self-hosted runner service on this host. A runner can wedge
# (listener alive but not claiming queued jobs); a restart reconnects it.
cmd_restart() {
  if [[ "$(uname -s)" == "Linux" ]]; then
    # systemd matches the glob across every actions.runner.* unit at once.
    sudo systemctl restart 'actions.runner.*'
    systemctl list-units --type=service --no-legend --no-pager \
      'actions.runner.*' | awk '{print $1, $4}'
  else
    # launchd has no glob, so bounce each runner via its own svc.sh.
    local dir
    for dir in "$BASE_DIR"/actions-runner-*/; do
      [[ -f "$dir/svc.sh" ]] || continue
      ( cd "$dir" && ./svc.sh stop && ./svc.sh start ) \
        || echo "warning: failed to restart $dir" >&2
    done
  fi
  echo "Runners restarted."
}

main() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    add)     cmd_add "$@";;
    remove)  cmd_remove "$@";;
    list)    cmd_list "$@";;
    restart) cmd_restart "$@";;
    -h|--help|help|"") usage;;
    *) die "unknown command: $sub";;
  esac
}

# Run only when executed directly; stays silent when sourced (for tests).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
