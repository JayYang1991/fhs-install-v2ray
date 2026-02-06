#!/usr/bin/env bash
# shellcheck disable=SC2268
#
# create_vultr_instance.sh
# Reference: https://www.vultr.com/

# --- Configuration (Externalized with Defaults) ---
MY_REGION="${VULTR_REGION:-nrt}"
MY_PLAN="${VULTR_PLAN:-vc2-1c-1gb}"
MY_OS="${VULTR_OS:-2284}" # Ubuntu 24.04
MY_HOST="${VULTR_HOST:-jayyang}"
MY_LABEL="${VULTR_LABEL:-ubuntu_2404}"
MY_TAG="${VULTR_TAG:-v2ray}"
MY_SSH_KEYS="${VULTR_SSH_KEYS:-c5e8bf26-ab13-454a-a827-c2afff006a67,fa784b8e-c8d9-40d3-ab66-c7b0177a4013}"
SCRIPT_ID="${VULTR_SCRIPT_ID:-89005eb6-6e67-40fb-b873-c8399295f05e}"
REPO_BRANCH="${V2RAY_REPO_BRANCH:-master}"

# --- Internal Variables ---
VPS_IP=""
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# --- Helper Functions ---
show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -h, --help            Show this help message"
  echo ""
  echo "Environment Variables:"
  echo "  VULTR_REGION, VULTR_PLAN, VULTR_OS, VULTR_SSH_KEYS, VULTR_SCRIPT_ID"
  echo ""
  echo "sing-box Configuration:"
  echo "  SINGBOX_PORT (default: 443)"
  echo "  SINGBOX_DOMAIN (default: www.cloudflare.com)"
  echo "  SINGBOX_UUID (default: auto)"
  echo "  SINGBOX_SHORT_ID (default: auto)"
  echo "  SINGBOX_LOG_LEVEL (default: info)"
}

log() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
  echo -e "${RED}[WARN]${NC} $1"
}

check_dependencies() {
  local deps=("vultr-cli" "curl" "ssh" "sed" "awk")
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
      echo "Error: Dependency '$dep' is missing. Please install it."
      exit 1
    fi
  done
}

is_private_ip() {
  local ip=$1
  # Check for RFC 1918 (10.x, 172.16-31.x, 192.168.x) and CGNAT (100.64-127.x)
  if [[ $ip =~ ^10\. ]] ||
    [[ $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] ||
    [[ $ip =~ ^192\.168\. ]] ||
    [[ $ip =~ ^100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\. ]]; then
    return 0
  fi
  return 1
}

get_vps_ip() {
  log "Fetching VPS IP for label: $MY_LABEL..."
  # Try IPv4 first
  VPS_IP=$(vultr-cli instance list | grep "$MY_LABEL" | awk '{print $2}')

  local vps_id
  vps_id=$(vultr-cli instance list | grep "$MY_LABEL" | awk '{print $1}')

  # Only if IPv4 is present and it is a private IP, try getting IPv6
  if [[ -n "$VPS_IP" && "$VPS_IP" != "0.0.0.0" ]] && is_private_ip "$VPS_IP"; then
    log "IPv4 ($VPS_IP) is invalid or private. Attempting to fetch IPv6..."
    if [[ -n "$vps_id" ]]; then
      # Try specific IPv6 list first
      VPS_IP=$(vultr-cli instance ipv6 list "$vps_id" | grep -v "IP" | grep -v "==" | head -n1 | awk '{print $1}')

      # If still empty, try instance get
      if [[ -z "$VPS_IP" ]]; then
        VPS_IP=$(vultr-cli instance get "$vps_id" | grep "V6 MAIN IP" | awk '{print $4}')
      fi
    fi
  fi

  # Check if we got an IP (v4 or v6)
  if [[ -z "$VPS_IP" || "$VPS_IP" == "0.0.0.0" ]]; then
    return 1
  fi
  return 0
}

check_ssh_until_success() {
  local host="$1"
  local port="${2:-22}"
  local timeout="${3:-4}"
  local max_attempts="${4:-60}"
  local interval="${5:-5}"

  log "Waiting for SSH to become available on $host:$port (verifying root login)..."
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    local output
    # Use whoami to ensure we are actually logged in as root
    if output=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout="$timeout" -l root -p "$port" "$host" "whoami" 2> /dev/null); then
      if [[ "$output" == "root" ]]; then
        log "First SSH connection successful as root."
        # Wait 2 seconds and check again to ensure stability
        sleep 2
        if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout="$timeout" -l root -p "$port" "$host" "true" 2> /dev/null; then
          log "SSH connection verified and stable."
          return 0
        fi
        log "SSH connection was unstable, retrying..."
      fi
    fi
    [[ $attempt -lt $max_attempts ]] && sleep "$interval"
  done
  return 1
}

install_singbox() {
  local port="${SINGBOX_PORT:-443}"
  local domain="${SINGBOX_DOMAIN:-www.cloudflare.com}"
  local uuid="${SINGBOX_UUID:-auto}"
  local short_id="${SINGBOX_SHORT_ID:-auto}"
  local log_level="${SINGBOX_LOG_LEVEL:-info}"
  local remote_client_config=""
  local tmp_client_config

  local output
  # shellcheck disable=SC2087
  output=$(
    ssh -T -o StrictHostKeyChecking=no "root@${VPS_IP}" << eof
    dpkg --configure -a || true
    if command -v sing-box > /dev/null 2>&1; then
      systemctl stop sing-box > /dev/null 2>&1 || true
      apt remove -y sing-box || true
      "rm" -rf /etc/sing-box || true
    fi
    curl -4 -L -q --retry 5 --retry-delay 10 --retry-max-time 60 -H 'Cache-Control: no-cache' -o /tmp/install-singbox-server.sh https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/${REPO_BRANCH}/install-singbox-server.sh
    bash /tmp/install-singbox-server.sh --port ${port} --domain ${domain} --uuid ${uuid} --short-id ${short_id} --log-level ${log_level}
eof
  )
  local ret_val=$?

  if [[ $ret_val -ne 0 ]]; then
    echo "error: 远端安装 sing-box 失败"
    return 1
  fi

  remote_client_config=$(echo "$output" | awk -F': ' '/客户端配置文件/ {print $2}' | tail -n 1 | tr -d '\r')
  if [[ -z "$remote_client_config" ]]; then
    echo "error: 未从远端输出获取客户端配置文件路径"
    return 1
  fi

  tmp_client_config=$(mktemp -p /tmp singbox_client_config.XXXXXX.json)
  if ! scp -o StrictHostKeyChecking=no "root@${VPS_IP}:${remote_client_config}" "$tmp_client_config" > /dev/null 2>&1; then
    echo "error: 下载远端客户端配置文件失败: $remote_client_config"
    return 1
  fi
  if [[ ! -s "$tmp_client_config" ]]; then
    echo "error: 本地客户端配置文件为空: $tmp_client_config"
    return 1
  fi

  echo "客户端配置文件已保存到本地: $tmp_client_config"
}

# --- Main Logic ---
main() {
  # Parse Arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help)
        show_help
        exit 0
        ;;
      *)
        warn "Unknown parameter passed: $1"
        show_help
        exit 1
        ;;
    esac
  done

  check_dependencies

  if get_vps_ip; then
    log "Instance already exists with IP: $VPS_IP"
  else
    log "Instance does not exist. Creating new instance..."
    if ! vultr-cli instance create --region="$MY_REGION" --plan="$MY_PLAN" --os="$MY_OS" --script-id="$SCRIPT_ID" --host="$MY_HOST" --label="$MY_LABEL" --tags="$MY_TAG" --ssh-keys="$MY_SSH_KEYS" --ipv6; then
      warn "Failed to create instance."
      exit 1
    fi

    log "Waiting for IP assignment..."
    while ! get_vps_ip; do
      sleep 2
    done
    log "New VPS IP: $VPS_IP"

    if ! check_ssh_until_success "$VPS_IP"; then
      warn "SSH failed to become available. Manual check required."
      exit 1
    fi
  fi

  install_singbox

}

main "$@"
