#!/bin/bash
# Refactored create_vultr_instance.sh

# --- Configuration (Externalized with Defaults) ---
MY_REGION="${VULTR_REGION:-ewr}"
MY_PLAN="${VULTR_PLAN:-vc2-1c-0.5gb-v6}"
MY_OS="${VULTR_OS:-2625}" # Ubuntu 22.04
MY_HOST="${VULTR_HOST:-jayyang}"
MY_LABEL="${VULTR_LABEL:-ubuntu_2204}"
MY_TAG="${VULTR_TAG:-v2ray}"
MY_SSH_KEYS="${VULTR_SSH_KEYS:-c5e8bf26-ab13-454a-a827-c2afff006a67,fa784b8e-c8d9-40d3-ab66-c7b0177a4013}"
SCRIPT_ID="${VULTR_SCRIPT_ID:-b587aa57-c65c-4dbd-a7f9-903be3d7b0e7}"
REPO_BRANCH="${V2RAY_REPO_BRANCH:-master}"
ENABLE_LOCAL_CONFIG="${ENABLE_LOCAL_CONFIG:-false}"

# --- Internal Variables ---
VPS_IP=""
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# --- Helper Functions ---
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

get_vps_ip() {
    log "Fetching VPS IP for label: $MY_LABEL..."
    # Try IPv4 first
    VPS_IP=$(vultr-cli instance list | grep "$MY_LABEL" | awk '{print $2}')
    
    # If IPv4 is missing or 0.0.0.0, try getting it via instance ID
    if [[ -z "$VPS_IP" || "$VPS_IP" == "0.0.0.0" ]]; then
        local vps_id
        vps_id=$(vultr-cli instance list | grep "$MY_LABEL" | awk '{print $1}')
        if [[ -n "$vps_id" ]]; then
            VPS_IP=$(vultr-cli instance get "$vps_id" | grep "MAIN IP" | head -n1 | awk '{print $4}')
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
    
    log "Waiting for SSH to become available on $host:$port..."
    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout="$timeout" -l root -p "$port" "$host" "echo 'ready'" >/dev/null 2>&1; then
            log "SSH connection successful."
            return 0
        fi
        [[ $attempt -lt $max_attempts ]] && sleep "$interval"
    done
    return 1
}

install_v2ray() {
    log "Installing V2Ray on VPS ($VPS_IP)..."
    ssh -T -o StrictHostKeyChecking=no "root@${VPS_IP}" << eof
    bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/${REPO_BRANCH}/install-v2ray.sh) --mode proxy-server
eof
    if [[ $? -eq 0 ]]; then
        log "V2Ray installation on $VPS_IP success."
    else
        warn "V2Ray installation failed."
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

# --- Main Logic ---
main() {
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
    
    if [[ "$ENABLE_LOCAL_CONFIG" == "true" ]]; then
        update_local_v2ray_agent_config
    else
        log "Skipping local configuration update (ENABLE_LOCAL_CONFIG is not true)."
    fi
}

main "$@"



