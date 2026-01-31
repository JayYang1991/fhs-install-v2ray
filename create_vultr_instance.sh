#!/bin/bash
# Refactored create_vultr_instance.sh

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
ENABLE_LOCAL_CONFIG="${ENABLE_LOCAL_CONFIG:-false}"
ENABLE_CLASH_CONFIG="${ENABLE_CLASH_CONFIG:-false}"
CLASH_CONFIG_PATH="${CLASH_CONFIG_PATH:-$HOME/.local/share/io.github.clash-verge-rev.clash-verge-rev/vultr-private.yaml}"

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
    echo "  -u, --update-local    Enable local V2Ray configuration update (default: disabled)"
    echo "  -c, --update-clash    Enable local Clash configuration update (default: disabled)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  VULTR_REGION, VULTR_PLAN, VULTR_OS, VULTR_SSH_KEYS, VULTR_SCRIPT_ID"
    echo "  ENABLE_LOCAL_CONFIG=true, ENABLE_CLASH_CONFIG=true"
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
    if [[ $ip =~ ^10\. ]] || \
       [[ $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
       [[ $ip =~ ^192\.168\. ]] || \
       [[ $ip =~ ^100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\. ]]; then
        return 0
    fi
    return 1
}

get_vps_ip() {
    log "Fetching VPS IP for label: $MY_LABEL..."
    # Try IPv4 first
    VPS_IP=$(vultr-cli instance list | grep "$MY_LABEL" | awk '{print $2}')
    
    local vps_id=$(vultr-cli instance list | grep "$MY_LABEL" | awk '{print $1}')

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
    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        local output
        # Use whoami to ensure we are actually logged in as root
        if output=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout="$timeout" -l root -p "$port" "$host" "whoami" 2>/dev/null); then
            if [[ "$output" == "root" ]]; then
                log "First SSH connection successful as root."
                # Wait 2 seconds and check again to ensure stability
                sleep 2
                if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout="$timeout" -l root -p "$port" "$host" "true" 2>/dev/null; then
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

install_v2ray() {
    log "Installing V2Ray on VPS ($VPS_IP)..."
    ssh -T -o StrictHostKeyChecking=no "root@${VPS_IP}" << eof
    export DEBIAN_FRONTEND=noninteractive
    dpkg --configure -a || true
    apt update || true
    bash <(curl -L -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/${REPO_BRANCH}/install-v2ray.sh) --mode proxy-server
eof
    if [[ $? -eq 0 ]]; then
        log "V2Ray installation on $VPS_IP success."
    else
        warn "V2Ray installation failed."
        return 1
    fi
}

install_singbox() {
    local port="${SINGBOX_PORT:-443}"
    local domain="${SINGBOX_DOMAIN:-www.cloudflare.com}"
    local uuid="${SINGBOX_UUID:-auto}"
    local short_id="${SINGBOX_SHORT_ID:-auto}"
    local log_level="${SINGBOX_LOG_LEVEL:-info}"

    log "Installing sing-box on VPS ($VPS_IP)..."
    log "Parameters: port=$port, domain=$domain, uuid=$uuid, short_id=$short_id"

    local output
    output=$(ssh -T -o StrictHostKeyChecking=no "root@${VPS_IP}" << eof
    export DEBIAN_FRONTEND=noninteractive
    dpkg --configure -a || true
    apt update || true
    bash <(curl -L -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/${REPO_BRANCH}/install-singbox-server.sh) --port ${port} --domain ${domain} --uuid ${uuid} --short-id ${short_id} --log-level ${log_level}
eof
)
    local ret_val=$?
    echo "$output"

    if [[ $ret_val -eq 0 ]]; then
        log "sing-box installation on $VPS_IP success."
        # Capture parameters from output
        SINGBOX_PUBLIC_KEY=$(echo "$output" | grep "Reality 公钥:" | awk '{print $3}' | tr -d '\r')
        SINGBOX_ACTUAL_UUID=$(echo "$output" | grep "UUID:" | awk '{print $2}' | tr -d '\r')
        SINGBOX_ACTUAL_SHORT_ID=$(echo "$output" | grep "short_id:" | awk '{print $2}' | tr -d '\r')
        
        if [[ -z "$SINGBOX_PUBLIC_KEY" ]]; then
            warn "Could not capture Reality Public Key from remote output."
        else
            log "Captured Reality Public Key: $SINGBOX_PUBLIC_KEY"
        fi

        if [[ -z "$SINGBOX_ACTUAL_UUID" ]]; then
            warn "Could not capture UUID from remote output."
        else
            log "Captured Actual UUID: $SINGBOX_ACTUAL_UUID"
        fi

        if [[ -z "$SINGBOX_ACTUAL_SHORT_ID" ]]; then
            warn "Could not capture Short ID from remote output."
        else
            log "Captured Actual Short ID: $SINGBOX_ACTUAL_SHORT_ID"
        fi
    else
        warn "sing-box installation failed."
        return 1
    fi
}

set_env_var() {
    local var_name="$1"
    local var_value="$2"
    local file="$3"
    if grep -q "^export ${var_name}=" "$file"; then
        sed -i "s|^export ${var_name}=.*|export ${var_name}=\"${var_value}\"|" "$file"
    else
        echo "export ${var_name}=\"${var_value}\"" >> "$file"
    fi
}

update_local_v2ray_agent_config() {
    local v2ray_config_file="/usr/local/etc/v2ray/config.json"
    local download_config_link="https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/${REPO_BRANCH}/proxy_client_config.json"
    local tmp_file
    tmp_file=$(mktemp)

    log "Updating local config for server: $VPS_IP"
    if ! curl -R -H 'Cache-Control: no-cache' -o "$tmp_file" "$download_config_link"; then
        warn "Failed to download client config template."
        rm -f "$tmp_file"
        return 1
    fi

    # Update .bashrc
    if [[ -f "$HOME/.bash_profile" ]]; then
        set_env_var "V2RAY_PROXY_SERVER_IP" "$VPS_IP" "$HOME/.bash_profile"
    elif [[ -f "$HOME/.bashrc" ]]; then
        set_env_var "V2RAY_PROXY_SERVER_IP" "$VPS_IP" "$HOME/.bashrc"
    fi

    # Update dynamic config
    sed -i "s|{V2RAY_PROXY_SERVER_IP}|$VPS_IP|g" "$tmp_file"
    sed -i "s|{V2RAY_PROXY_ID}|${V2RAY_PROXY_ID}|g" "$tmp_file"
    sed -i "s|{V2RAY_REVERSE_SERVER_IP}|${V2RAY_REVERSE_SERVER_IP}|g" "$tmp_file"
    sed -i "s|{V2RAY_REVERSE_ID}|${V2RAY_REVERSE_ID}|g" "$tmp_file"

    if sudo cp "$tmp_file" "$v2ray_config_file"; then
        log "Template successfully applied to $v2ray_config_file"
        if sudo systemctl restart v2ray.service; then
            log "Local V2Ray service restarted successfully."
        else
            warn "Failed to restart local V2Ray service."
        fi
    else
        warn "Failed to copy config to $v2ray_config_file"
    fi
    rm -f "$tmp_file"
}

update_clash_config() {
    if [[ ! -f "$CLASH_CONFIG_PATH" ]]; then
        warn "Clash config file not found: $CLASH_CONFIG_PATH"
        return 1
    fi

    if [[ -z "$SINGBOX_PUBLIC_KEY" ]]; then
        warn "Cannot update Clash config: Missing Reality Public Key."
        return 1
    fi

    log "Updating local Clash config: $CLASH_CONFIG_PATH"

python3 - <<EOF
import yaml
import sys
import os

config_path = "$CLASH_CONFIG_PATH"
server_ip = "$VPS_IP"
port = int("${SINGBOX_PORT:-443}")
uuid = "$SINGBOX_ACTUAL_UUID"
domain = "${SINGBOX_DOMAIN:-www.cloudflare.com}"
public_key = "$SINGBOX_PUBLIC_KEY"
short_id = "$SINGBOX_ACTUAL_SHORT_ID"

try:
    with open(config_path, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)

    if not config:
        config = {}

    # Update or add proxy
    proxies = config.get('proxies', [])
    proxy_name = f"sing-box-{server_ip}"
    
    # Generate UUID if auto
    actual_uuid = uuid
    if actual_uuid == "auto" or not actual_uuid:
        # In this script, if it was auto, the remote generated it. 
        # But wait, create_vultr_instance.sh doesn't know the remote UUID unless we capture it too.
        pass

    new_proxy = {
        'name': proxy_name,
        'type': 'vless',
        'server': server_ip,
        'port': port,
        'uuid': actual_uuid,
        'network': 'tcp',
        'tls': True,
        'udp': True,
        'flow': 'xtls-rprx-vision',
        'servername': domain,
        'reality-opts': {
            'public-key': public_key,
            'short-id': short_id
        },
        'client-fingerprint': 'chrome'
    }

    # Find if proxy already exists by name
    found = False
    for i, p in enumerate(proxies):
        if p.get('name') == proxy_name:
            proxies[i] = new_proxy
            found = True
            break
    
    if not found:
        proxies.append(new_proxy)
    
    config['proxies'] = proxies

    # Ensure proxy is in PROXY group
    proxy_groups = config.get('proxy-groups', [])
    found_group = False
    for group in proxy_groups:
        if group.get('name') == 'PROXY':
            group_proxies = group.get('proxies', [])
            if proxy_name not in group_proxies:
                group_proxies.insert(0, proxy_name)
                group['proxies'] = group_proxies
            found_group = True
            break
    
    if not found_group:
        proxy_groups.append({
            'name': 'PROXY',
            'type': 'select',
            'proxies': [proxy_name, 'DIRECT']
        })
    
    config['proxy-groups'] = proxy_groups

    # Write back
    with open(config_path, 'w', encoding='utf-8') as f:
        yaml.dump(config, f, allow_unicode=True, sort_keys=False)
    
    print(f"info: Successfully updated node {proxy_name}")

except Exception as e:
    print(f"error: Failed to update config: {str(e)}")
    sys.exit(1)
EOF

    if [[ $? -eq 0 ]]; then
        log "Local Clash configuration updated successfully."
    else
        warn "Failed to update local Clash configuration."
    fi
}

# --- Main Logic ---
main() {
    # Parse Arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -u|--update-local) ENABLE_LOCAL_CONFIG="true"; shift ;;
            -c|--update-clash) ENABLE_CLASH_CONFIG="true"; shift ;;
            --clash-config-path) CLASH_CONFIG_PATH="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) warn "Unknown parameter passed: $1"; show_help; exit 1 ;;
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

    install_v2ray
    install_singbox
    
    if [[ "$ENABLE_LOCAL_CONFIG" == "true" ]]; then
        update_local_v2ray_agent_config
    fi

    if [[ "$ENABLE_CLASH_CONFIG" == "true" ]]; then
        update_clash_config
    fi
}

main "$@"



