#!/usr/bin/env bash
# shellcheck disable=SC2317
# References:
# - sing-box Clash API compatible endpoint: /proxies/{selector}
# - curl exit code 28 means operation timeout

set -euo pipefail

# Website used for connectivity checks (example: https://www.gstatic.com/generate_204)
TEST_URL='https://www.gstatic.com/generate_204'
# sing-box external controller address (example: http://127.0.0.1:9090)
API_BASE='http://127.0.0.1:9090'
# Selector name in sing-box (optional, auto-discovered when empty)
SELECTOR_NAME=''
# Candidate outbound chain list, comma separated (optional, auto-discovered when empty)
CHAIN_NAMES=''
# Monitoring interval in seconds
CHECK_INTERVAL=15
# Request timeout in seconds
CHECK_TIMEOUT=8
# How many consecutive timeouts before switching
TIMEOUT_THRESHOLD=2
# Optional test proxy for curl (example: http://127.0.0.1:7890 or socks5h://127.0.0.1:1080)
TEST_PROXY=''
# State file for current index
STATE_FILE='/tmp/singbox-failover-index.state'
USER_SET_SELECTOR=0
USER_SET_CHAINS=0
CURRENT_CHAIN_FROM_API=''
LIST_GROUPS_ONLY=0

red=$(tput setaf 1)
green=$(tput setaf 2)
aoi=$(tput setaf 6)
reset=$(tput sgr0)

usage() {
  cat << USAGE
Usage:
  bash monitor-singbox-failover.sh \\
    --list-groups \\
    [--api <controller_url>]

  bash monitor-singbox-failover.sh \\
    --url <test_url> \\
    --api <controller_url> \\
    [--selector <selector_name>] \\
    [--chains <name1,name2,...>] \\
    [--interval <seconds>] \\
    [--timeout <seconds>] \\
    [--threshold <count>] \\
    [--proxy <http://127.0.0.1:7890>] \\
    [--state-file </tmp/xxx.state>]

Example:
  bash monitor-singbox-failover.sh \\
    --url https://www.gstatic.com/generate_204 \\
    --api http://127.0.0.1:9090 \\
    --interval 15 \\
    --timeout 8 \\
    --threshold 2 \\
    --proxy http://127.0.0.1:7890

Note:
  --selector and --chains are optional.
  If omitted, script auto-discovers selector and candidate chains from sing-box API.
  Use --list-groups to only print proxy groups and members from API, then exit.
USAGE
}

log_info() {
  echo "${aoi}info:${reset} $*"
}

log_ok() {
  echo "${green}info:${reset} $*"
}

log_error() {
  echo "${red}error:${reset} $*"
}

# curl wrapper with retry defaults for controller requests.
curl_with_retry() {
  "$(type -P curl)" -L -q --retry 5 --retry-delay 2 --retry-max-time 30 \
    --user-agent 'singbox-failover-monitor/1.0' --connect-timeout 5 "$@"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --url)
        TEST_URL="$2"
        shift 2
        ;;
      --list-groups)
        LIST_GROUPS_ONLY=1
        shift 1
        ;;
      --api)
        API_BASE="$2"
        shift 2
        ;;
      --selector)
        SELECTOR_NAME="$2"
        USER_SET_SELECTOR=1
        shift 2
        ;;
      --chains)
        CHAIN_NAMES="$2"
        USER_SET_CHAINS=1
        shift 2
        ;;
      --interval)
        CHECK_INTERVAL="$2"
        shift 2
        ;;
      --timeout)
        CHECK_TIMEOUT="$2"
        shift 2
        ;;
      --threshold)
        TIMEOUT_THRESHOLD="$2"
        shift 2
        ;;
      --proxy)
        TEST_PROXY="$2"
        shift 2
        ;;
      --state-file)
        STATE_FILE="$2"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        log_error "unknown arg: $1"
        usage
        exit 1
        ;;
    esac
  done
}

validate_args() {
  if [[ -z "$API_BASE" ]]; then
    log_error '--api is required'
    exit 1
  fi

  if [[ "$LIST_GROUPS_ONLY" -eq 0 && -z "$TEST_URL" ]]; then
    log_error '--url is required when not using --list-groups'
    exit 1
  fi

  if ! [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ && "$CHECK_TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT_THRESHOLD" =~ ^[0-9]+$ ]]; then
    log_error '--interval, --timeout and --threshold must be integers'
    exit 1
  fi

  if [[ "$TIMEOUT_THRESHOLD" -eq 0 ]]; then
    log_error '--threshold must be >= 1'
    exit 1
  fi
}

list_proxy_groups() {
  local api_url proxy_json output parse_status

  api_url="${API_BASE%/}/proxies"
  proxy_json="$(curl_with_retry -sS -f "$api_url")" || {
    log_error "failed to fetch proxy list from API: $api_url"
    return 1
  }

  output="$(
    PROXY_JSON="$proxy_json" python3 - << 'PY'
import json
import os
import sys

data = json.loads(os.environ["PROXY_JSON"])
proxies = data.get("proxies", {})

groups = []
for name, node in proxies.items():
    if not isinstance(node, dict):
        continue
    members = node.get("all")
    if not isinstance(members, list) or len(members) == 0:
        continue
    group_type = node.get("type", "unknown")
    now = node.get("now", "")
    if not isinstance(now, str):
        now = ""
    clean_members = [x for x in members if isinstance(x, str) and x]
    groups.append((name, group_type, now, clean_members))

if not groups:
    print("ERROR=no proxy groups with non-empty all list found")
    sys.exit(2)

groups.sort(key=lambda x: x[0].lower())
for index, (name, group_type, now, members) in enumerate(groups, start=1):
    current = now if now else "-"
    print(f"[{index}] group={name} type={group_type} current={current}")
    for member in members:
        print(f"  - {member}")
PY
  )"
  parse_status=$?

  if [[ "$parse_status" -ne 0 ]]; then
    if [[ -n "$output" ]]; then
      log_error "$output"
    else
      log_error 'failed to parse proxy groups'
    fi
    return 1
  fi

  log_info "proxy groups from ${API_BASE%/}:"
  echo "$output"
  return 0
}

discover_runtime_config_from_api() {
  local api_url proxy_json parsed_result parse_status

  api_url="${API_BASE%/}/proxies"
  proxy_json="$(curl_with_retry -sS -f "$api_url")" || {
    log_error "failed to fetch proxy list from API: $api_url"
    return 1
  }

  parsed_result="$(
    PROXY_JSON="$proxy_json" python3 - "$SELECTOR_NAME" "$CHAIN_NAMES" << 'PY'
import json
import os
import sys

selector_input = sys.argv[1].strip()
chains_input = sys.argv[2].strip()

data = json.loads(os.environ["PROXY_JSON"])
proxies = data.get("proxies", {})

def is_selector(node):
    return (
        isinstance(node, dict)
        and node.get("type") == "Selector"
        and isinstance(node.get("all"), list)
        and len(node.get("all")) > 0
    )

selected = ""
if selector_input and selector_input in proxies and is_selector(proxies[selector_input]):
    selected = selector_input

if not selected:
    preferred = proxies.get("PROXY")
    if is_selector(preferred):
        selected = "PROXY"

if not selected:
    for name, node in proxies.items():
        if is_selector(node):
            selected = name
            break

if not selected:
    print("ERROR=no selector with non-empty all list found")
    sys.exit(2)

selected_node = proxies[selected]
all_chains = [x for x in selected_node.get("all", []) if isinstance(x, str) and x]
if chains_input:
    chains = chains_input
else:
    chains = ",".join(all_chains)

if not chains:
    print("ERROR=empty chain list")
    sys.exit(3)

current = selected_node.get("now", "")
if not isinstance(current, str):
    current = ""

print(f"SELECTOR_NAME={selected}")
print(f"CHAIN_NAMES={chains}")
print(f"CURRENT_CHAIN={current}")
PY
  )"
  parse_status=$?

  if [[ "$parse_status" -ne 0 ]]; then
    if [[ -n "$parsed_result" ]]; then
      log_error "$parsed_result"
    else
      log_error 'failed to parse sing-box API response'
    fi
    return 1
  fi

  while IFS='=' read -r key value; do
    case "$key" in
      SELECTOR_NAME)
        if [[ "$USER_SET_SELECTOR" -eq 0 ]]; then
          SELECTOR_NAME="$value"
        fi
        ;;
      CHAIN_NAMES)
        if [[ "$USER_SET_CHAINS" -eq 0 ]]; then
          CHAIN_NAMES="$value"
        fi
        ;;
      CURRENT_CHAIN)
        CURRENT_CHAIN_FROM_API="$value"
        ;;
      *) ;;
    esac
  done <<< "$parsed_result"

  if [[ -z "$SELECTOR_NAME" || -z "$CHAIN_NAMES" ]]; then
    log_error 'selector/chains are empty after API discovery'
    return 1
  fi

  return 0
}

load_chain_array() {
  IFS=',' read -r -a CHAIN_ARRAY <<< "$CHAIN_NAMES"
  if [[ "${#CHAIN_ARRAY[@]}" -eq 0 ]]; then
    log_error 'no chain found in discovered chains'
    exit 1
  fi
}

load_current_index() {
  local default_index=0

  if [[ -f "$STATE_FILE" ]]; then
    CURRENT_INDEX="$(cat "$STATE_FILE" 2> /dev/null || echo "$default_index")"
  else
    CURRENT_INDEX="$default_index"
  fi

  if ! [[ "$CURRENT_INDEX" =~ ^[0-9]+$ ]]; then
    CURRENT_INDEX="$default_index"
  fi

  if [[ "$CURRENT_INDEX" -ge "${#CHAIN_ARRAY[@]}" ]]; then
    CURRENT_INDEX="$default_index"
  fi
}

sync_current_index_with_api() {
  local index

  if [[ -z "$CURRENT_CHAIN_FROM_API" ]]; then
    return 0
  fi

  for index in "${!CHAIN_ARRAY[@]}"; do
    if [[ "${CHAIN_ARRAY[$index]}" == "$CURRENT_CHAIN_FROM_API" ]]; then
      CURRENT_INDEX="$index"
      save_current_index
      return 0
    fi
  done

  return 0
}

save_current_index() {
  echo "$CURRENT_INDEX" > "$STATE_FILE"
}

switch_to_next_chain() {
  local next_index next_chain api_url request_body

  next_index=$(((CURRENT_INDEX + 1) % ${#CHAIN_ARRAY[@]}))
  next_chain="${CHAIN_ARRAY[$next_index]}"
  api_url="${API_BASE%/}/proxies/${SELECTOR_NAME}"
  request_body="{\"name\":\"${next_chain}\"}"

  log_info "timeout threshold reached, switching selector '${SELECTOR_NAME}' -> '${next_chain}'"

  if curl_with_retry -sS -f -X PUT "$api_url" \
    -H 'Content-Type: application/json' \
    -d "$request_body" > /dev/null; then
    CURRENT_INDEX="$next_index"
    save_current_index
    log_ok "selector switched to '${next_chain}'"
    return 0
  fi

  log_error "failed to call sing-box API: $api_url"
  return 1
}

check_connectivity_once() {
  local curl_bin exit_code
  curl_bin="$(type -P curl)"

  if [[ -n "$TEST_PROXY" ]]; then
    if "$curl_bin" -sS -o /dev/null --max-time "$CHECK_TIMEOUT" --connect-timeout "$CHECK_TIMEOUT" \
      --proxy "$TEST_PROXY" "$TEST_URL"; then
      return 0
    fi
  else
    if "$curl_bin" -sS -o /dev/null --max-time "$CHECK_TIMEOUT" --connect-timeout "$CHECK_TIMEOUT" \
      "$TEST_URL"; then
      return 0
    fi
  fi

  exit_code=$?
  if [[ "$exit_code" -eq 28 ]]; then
    return 28
  fi

  return 1
}

main_loop() {
  local timeout_count=0 check_result current_chain

  while true; do
    current_chain="${CHAIN_ARRAY[$CURRENT_INDEX]}"
    check_result=0

    if check_connectivity_once; then
      timeout_count=0
      log_ok "connectivity ok via '${current_chain}'"
    else
      check_result=$?
      if [[ "$check_result" -eq 28 ]]; then
        timeout_count=$((timeout_count + 1))
        log_error "connect timeout (${timeout_count}/${TIMEOUT_THRESHOLD}) on '${current_chain}'"
        if [[ "$timeout_count" -ge "$TIMEOUT_THRESHOLD" ]]; then
          timeout_count=0
          switch_to_next_chain || true
        fi
      else
        log_error "connect failed (non-timeout), keep current chain '${current_chain}'"
      fi
    fi

    sleep "$CHECK_INTERVAL"
  done
}

main() {
  parse_args "$@"
  validate_args

  if [[ "$LIST_GROUPS_ONLY" -eq 1 ]]; then
    list_proxy_groups
    exit 0
  fi

  discover_runtime_config_from_api
  load_chain_array
  load_current_index
  sync_current_index_with_api

  log_info "monitor started"
  log_info "test url: $TEST_URL"
  log_info "controller: ${API_BASE%/}"
  log_info "selector: $SELECTOR_NAME"
  log_info "chains: $CHAIN_NAMES"
  log_info "interval=${CHECK_INTERVAL}s timeout=${CHECK_TIMEOUT}s threshold=${TIMEOUT_THRESHOLD}"
  if [[ -n "$TEST_PROXY" ]]; then
    log_info "test proxy: $TEST_PROXY"
  fi

  main_loop
}

main "$@"
