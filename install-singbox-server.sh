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

curl() {
  $(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
}

install_singbox() {
  echo "${aoi}info: 正在安装 sing-box...${reset}"

  if curl -fsSL https://sing-box.app/install.sh | sh; then
    local installed_version
    installed_version=$(sing-box version 2>/dev/null | head -n1 || echo "unknown")
    echo "${green}info: sing-box 已安装: $installed_version${reset}"
  else
    echo "${red}error: 安装 sing-box 失败${reset}"
    exit 1
  fi

  if ! command -v sing-box >/dev/null 2>&1; then
    echo "${red}error: sing-box 命令未找到${reset}"
    exit 1
  fi
}

generate_keys() {
  echo "${aoi}info: 正在生成密钥...${reset}"

  if [[ "$UUID" == "auto" ]]; then
    UUID=$(uuidgen)
    if [[ -z "$UUID" ]]; then
      echo "${red}error: 生成 UUID 失败${reset}"
      exit 1
    fi
  fi

  if ! KEY_OUTPUT=$(sing-box generate reality-keypair 2>&1); then
    echo "${red}error: 生成 Reality 密钥失败${reset}"
    exit 1
  fi

  PRIVATE_KEY=$(echo "$KEY_OUTPUT" | awk '/PrivateKey/ {print $2}')
  PUBLIC_KEY=$(echo "$KEY_OUTPUT" | awk '/PublicKey/ {print $2}')

  if [[ -z "$PRIVATE_KEY" ]] || [[ -z "$PUBLIC_KEY" ]]; then
    echo "${red}error: 解析密钥失败${reset}"
    exit 1
  fi

  if [[ "$SHORT_ID" == "auto" ]]; then
    SHORT_ID=$(openssl rand -hex 4)
    if [[ -z "$SHORT_ID" ]]; then
      echo "${red}error: 生成 Short ID 失败${reset}"
      exit 1
    fi
  fi
}

write_config() {
  echo "${aoi}info: 正在写入配置文件...${reset}"

  mkdir -p /etc/sing-box || {
    echo "${red}error: 创建配置目录失败${reset}"
    exit 1
  }

  if ! cat > /etc/sing-box/config.json <<EOF
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
  then
    echo "${red}error: 写入配置文件失败${reset}"
    exit 1
  fi

  if ! sing-box check -c /etc/sing-box/config.json 2>/dev/null; then
    echo "${red}error: 配置文件验证失败${reset}"
    exit 1
  fi

  echo "${green}info: 配置文件验证通过${reset}"
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

  if ! systemctl enable sing-box; then
    echo "${red}error: 启用 sing-box 服务失败${reset}"
    exit 1
  fi

  if ! systemctl restart sing-box; then
    echo "${red}error: 启动 sing-box 服务失败${reset}"
    systemctl status sing-box --no-pager
    journalctl -u sing-box -n 20 --no-pager
    exit 1
  fi

  sleep 2

  if ! systemctl is-active --quiet sing-box; then
    echo "${red}error: sing-box 服务未运行${reset}"
    systemctl status sing-box --no-pager
    journalctl -u sing-box -n 20 --no-pager
    exit 1
  fi

  echo "${green}info: sing-box 服务已启动${reset}"
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

generate_clash_verge_config() {
  local server_ip
  server_ip=$(get_server_ip)

  if [[ -z "$server_ip" ]]; then
    echo "${red}error: 无法获取服务器 IP 地址${reset}"
    return 1
  fi

  cat <<EOF
proxies:
  - name: "sing-box-${server_ip}"
    type: vless
    server: ${server_ip}
    port: ${PORT}
    uuid: ${UUID}
    network: tcp
    tls: true
    udp: true
    servername: ${DOMAIN}
    skip-cert-verify: true
    client-fingerprint: chrome
    reality:
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
}

generate_clash_verge_subscription_url() {
  local clash_config
  clash_config=$(generate_clash_verge_config)

  if [[ -z "$clash_config" ]]; then
    return 1
  fi

  local subscription_url
  subscription_url=$(echo -n "$clash_config" | base64 -w 0)

  echo "$subscription_url"
}

print_info() {
  local server_ip
  server_ip=$(get_server_ip)

  echo ""
  echo "========================================"
  echo "${green}✅ sing-box Server 安装完成${reset}"
  echo ""
  echo "📌 客户端参数："
  echo "协议: VLESS"
  echo "地址: $server_ip"
  echo "端口: $PORT"
  echo "UUID: $UUID"
  echo "Reality 公钥: $PUBLIC_KEY"
  echo "SNI: $DOMAIN"
  echo "short_id: $SHORT_ID"
  echo "传输: TCP"
  echo ""
  echo "📌 Clash Verge 导入方式："
  echo ""
  echo "方式1 - 手动添加节点："
  echo "  点击「添加节点」→ 选择「VLESS」"
  echo "  填写上述参数"
  echo ""
  echo "方式2 - 导入配置文件："
  local config_file="/tmp/sing-box-clash-config.yaml"
  generate_clash_verge_config > "$config_file" 2>/dev/null || true
  if [[ -f "$config_file" ]]; then
    echo "  配置文件路径: $config_file"
    echo "  复制此路径或文件内容到 Clash Verge"
  fi
  echo ""
  echo "方式3 - 复制配置内容："
  echo "--- 配置开始 ---"
  generate_clash_verge_config
  echo "--- 配置结束 ---"
  echo ""
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
