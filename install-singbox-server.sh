#!/usr/bin/env bash
# shellcheck disable=SC2268
#
# sing-box Server Installation Script
# Reference: https://sing-box.sagernet.org/
#
# Environment Variables:
#   PORT              - Listening port (default: 443)
#   DOMAIN            - Server Name Indication (default: www.cloudflare.com)
#   UUID              - Client UUID (default: auto-generated)
#   SHORT_ID          - Reality short ID (default: auto-generated)
#   LOG_LEVEL         - Log level (default: info)
#
set -e

# ===================== Default Parameters =====================
PORT=${PORT:-443}
DOMAIN=${DOMAIN:-www.cloudflare.com}
UUID=${UUID:-auto}
SHORT_ID=${SHORT_ID:-auto}
LOG_LEVEL=${LOG_LEVEL:-info}

# ===================== Color Output =====================
red=$(tput setaf 1)
green=$(tput setaf 2)
aoi=$(tput setaf 6)
reset=$(tput sgr0)

# ===================== Functions =====================

check_if_running_as_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "${red}error: 请使用 root 运行${reset}"
    exit 1
  fi
}

identify_the_operating_system_and_architecture() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS="$ID"
  else
    echo "${red}error: 无法检测操作系统${reset}"
    exit 1
  fi
}

install_dependencies() {
  echo "${aoi}info: 正在安装依赖...${reset}"

  if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt install -y curl gnupg ca-certificates uuid-runtime openssl
  elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "fedora" ]]; then
    dnf install -y curl gnupg2 ca-certificates util-linux openssl
  elif [[ "$OS" == "arch" ]]; then
    pacman -S --noconfirm --needed curl gnupg ca-certificates util-linux openssl
  else
    echo "${red}error: 不支持的操作系统: $OS${reset}"
    exit 1
  fi
}

install_singbox() {
  echo "${aoi}info: 正在安装 sing-box...${reset}"

  if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://sing-box.sagernet.org/apt/gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/sagernet.gpg

    echo "deb [signed-by=/etc/apt/keyrings/sagernet.gpg] https://sing-box.sagernet.org/apt stable main" \
      > /etc/apt/sources.list.d/sagernet.list

    apt update
    apt install -y sing-box
  elif [[ "$OS" == "arch" ]]; then
    pacman -S --noconfirm --needed sing-box
  else
    echo "${red}error: 当前操作系统暂不支持自动安装 sing-box${reset}"
    exit 1
  fi
}

generate_keys() {
  echo "${aoi}info: 正在生成密钥...${reset}"

  if [[ "$UUID" == "auto" ]]; then
    UUID=$(uuidgen)
  fi

  KEY_OUTPUT=$(sing-box generate reality-keypair)
  PRIVATE_KEY=$(echo "$KEY_OUTPUT" | awk '/PrivateKey/ {print $2}')
  PUBLIC_KEY=$(echo "$KEY_OUTPUT" | awk '/PublicKey/ {print $2}')

  if [[ "$SHORT_ID" == "auto" ]]; then
    SHORT_ID=$(openssl rand -hex 4)
  fi
}

write_config() {
  echo "${aoi}info: 正在写入配置文件...${reset}"

  mkdir -p /etc/sing-box

  cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "$LOG_LEVEL",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        {
          "uuid": "$UUID"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$DOMAIN",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$DOMAIN",
            "server_port": 443
          },
          "private_key": "$PRIVATE_KEY",
          "short_id": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
}

configure_firewall() {
  echo "${aoi}info: 正在配置防火墙...${reset}"

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${PORT}/tcp" || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${PORT}/tcp" || true
    firewall-cmd --reload || true
  fi
}

start_service() {
  echo "${aoi}info: 正在启动 sing-box 服务...${reset}"

  systemctl enable sing-box
  systemctl restart sing-box
}

get_server_ip() {
  local server_ip=""
  
  if command -v curl >/dev/null 2>&1; then
    server_ip=$(curl -s -4 ifconfig.me 2>/dev/null) || \
    server_ip=$(curl -s -4 icanhazip.com 2>/dev/null) || \
    server_ip=$(curl -s -4 ipecho.net/plain 2>/dev/null)
  fi
  
  if [[ -z "$server_ip" ]] && command -v wget >/dev/null 2>&1; then
    server_ip=$(wget -q -O - ifconfig.me 2>/dev/null) || \
    server_ip=$(wget -q -O - icanhazip.com 2>/dev/null)
  fi
  
  echo "$server_ip"
}

generate_clash_verge_subscription() {
  local server_ip
  server_ip=$(get_server_ip)

  if [[ -z "$server_ip" ]]; then
    echo "${red}error: 无法获取服务器 IP 地址${reset}"
    return 1
  fi

  local clash_config
  clash_config=$(cat <<EOF
proxies:
  - name: "sing-box-${server_ip}"
    type: vless
    server: ${server_ip}
    port: ${PORT}
    uuid: ${UUID}
    network: tcp
    tls: true
    udp: true
    flow: ""
    servername: ${DOMAIN}
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - sing-box-${server_ip}
      - DIRECT

rules:
  - MATCH,PROXY
EOF
)

  local subscription_url
  subscription_url=$(echo -n "$clash_config" | base64 -w 0)

  echo "$subscription_url"
}

print_info() {
  echo ""
  echo "========================================"
  echo "${green}✅ sing-box Server 安装完成${reset}"
  echo ""
  echo "📌 客户端参数："
  echo "协议: VLESS"
  echo "地址: $(get_server_ip)"
  echo "端口: $PORT"
  echo "UUID: $UUID"
  echo "Reality 公钥: $PUBLIC_KEY"
  echo "SNI: $DOMAIN"
  echo "short_id: $SHORT_ID"
  echo "传输: TCP"
  echo ""
  echo "📌 Clash Verge 订阅链接："
  local subscription_url
  subscription_url=$(generate_clash_verge_subscription)
  if [[ -n "$subscription_url" ]]; then
    echo "base64://${subscription_url}"
  fi
  echo "========================================"
}

# ===================== Parse Arguments =====================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="$2"; shift 2 ;;
    --domain)
      DOMAIN="$2"; shift 2 ;;
    --uuid)
      UUID="$2"; shift 2 ;;
    --short-id)
      SHORT_ID="$2"; shift 2 ;;
    --log-level)
      LOG_LEVEL="$2"; shift 2 ;;
    *)
      echo "${red}error: 未知参数: $1${reset}"
      exit 1 ;;
  esac
done

# ===================== Main Function =====================
main() {
  echo "${aoi}▶ sing-box Server 自动安装开始${reset}"
  echo "端口: $PORT"
  echo "SNI: $DOMAIN"
  echo ""

  check_if_running_as_root
  identify_the_operating_system_and_architecture

  if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt update
  elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "fedora" ]]; then
    dnf check-update || true
  elif [[ "$OS" == "arch" ]]; then
    pacman -Sy --noconfirm
  fi

  install_dependencies
  install_singbox
  generate_keys
  write_config
  configure_firewall
  start_service
  print_info
}

main "$@"
