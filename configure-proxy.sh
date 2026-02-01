#!/usr/bin/env bash
# shellcheck disable=SC2268

# Script to configure proxy settings for terminal environment on Ubuntu 24.04
# Supports: shell (bash/zsh), code-server, docker

# You can set these variables before running the script:
# export PROXY_HOST='127.0.0.1'
# export PROXY_PORT='7897'
# export PROXY_TYPE='socks5'  # or 'http'
# export PROXY_USER='username'  # optional
# export PROXY_PASS='password'  # optional
# export NO_PROXY='localhost,127.0.0.1,::1'  # optional
PROXY_HOST=${PROXY_HOST:-127.0.0.1}
PROXY_PORT=${PROXY_PORT:-7897}
PROXY_TYPE=${PROXY_TYPE:-socks5}
PROXY_USER=${PROXY_USER:-}
PROXY_PASS=${PROXY_PASS:-}
NO_PROXY=${NO_PROXY:-localhost,127.0.0.1,::1}

# Color output
red=$(tput setaf 1)
green=$(tput setaf 2)
aoi=$(tput setaf 6)
reset=$(tput sgr0)

# Logging function
log() {
  local level="$1"
  local message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $message"
}

# Error handling function
error_exit() {
  local message="$1"
  log "ERROR" "$message"
  exit 1
}

# Warning function
warning() {
  local message="$1"
  log "WARNING" "$message"
}

# Info function
info() {
  local message="$1"
  log "INFO" "$message"
}

# Debug function
debug() {
  local message="$1"
  [[ "$DEBUG" == "1" ]] && log "DEBUG" "$message"
}

curl() {
  $(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
}

# Function to validate proxy host and port
validate_proxy_config() {
  debug "Validating proxy configuration: host=$PROXY_HOST, port=$PROXY_PORT, type=$PROXY_TYPE"
  
  # Validate port number (should be between 1-65535)
  if ! [[ "$PROXY_PORT" =~ ^[0-9]+$ ]] || [ "$PROXY_PORT" -lt 1 ] || [ "$PROXY_PORT" -gt 65535 ]; then
    error_exit "Invalid proxy port: $PROXY_PORT. Must be between 1 and 65535."
  fi

  # Validate host (basic check for IP or domain)
  if [[ -z "$PROXY_HOST" ]]; then
    error_exit "Proxy host cannot be empty."
  fi

  # Check that PROXY_TYPE is valid
  if [[ "$PROXY_TYPE" != 'http' ]] && [[ "$PROXY_TYPE" != 'socks5' ]]; then
    error_exit "Invalid proxy type. Must be 'http' or 'socks5'."
  fi

  debug "Proxy configuration validation passed"
}

check_if_running_as_root() {
  if [[ "$UID" -ne '0' ]]; then
    warning "This script must be run as root for system-wide configurations."
    warning "Some configurations (like docker) require root privileges."
    read -r -p "Continue without root privileges? [y/n] " cont_without_root
    if [[ x"${cont_without_root:0:1}" = x'y' ]]; then
      info "Continuing with limited privileges (shell and code-server only)..."
      NO_ROOT=1
    else
      error_exit "Root privileges required for system-wide configurations"
    fi
  fi
}

show_help() {
  cat << EOF
usage: $0 [OPTIONS]

Configure proxy settings for terminal environment on Ubuntu 24.04.

Applications:
  Shell (bash/zsh)    Configure proxy environment variables for current and future shells
  Code-server         Configure proxy settings for code-server
  Docker              Configure proxy settings for Docker daemon and containers

Options:
  -h, --host          Proxy host (default: 127.0.0.1)
  -p, --port          Proxy port (default: 7897)
  -t, --type          Proxy type: http or socks5 (default: socks5)
  -u, --user          Proxy username (optional)
  -w, --pass          Proxy password (optional)
  -n, --no-proxy      No proxy list (default: localhost,127.0.0.1,::1)
  -r, --remove        Remove all proxy configurations
  -s, --shell-only    Configure shell proxy only
  -c, --code-only     Configure code-server proxy only
  -d, --docker-only   Configure docker proxy only
  --show              Show current proxy configuration
  -H, --help          Show this help message

Environment Variables:
  PROXY_HOST          Proxy server host address
  PROXY_PORT          Proxy server port
  PROXY_TYPE          Proxy type: http or socks5
  PROXY_USER          Proxy username (optional)
  PROXY_PASS          Proxy password (optional)
  NO_PROXY            No proxy list (default: localhost,127.0.0.1,::1)

Examples:
  $0                                          # Configure all with default settings
  $0 -h 192.168.1.100 -p 8080 -t http       # Configure with custom settings
  $0 -h proxy.example.com -p 3128 -u user -w pass  # Configure with authentication
  $0 -n localhost,127.0.0.1,::1,docker-registry    # Custom no-proxy list
  $0 --remove                                # Remove all proxy configurations
  $0 --show                                  # Show current proxy configuration

EOF
  exit 0
}

get_proxy_url() {
  local proxy_type=$1
  local host=$2
  local port=$3
  local user=$4
  local pass=$5

  if [[ -n "$user" ]] && [[ -n "$pass" ]]; then
    echo "${proxy_type}://${user}:${pass}@${host}:${port}"
  else
    echo "${proxy_type}://${host}:${port}"
  fi
}

configure_shell_proxy() {
  info "Configuring shell proxy settings..."

  local http_proxy_url
  local https_proxy_url
  local all_proxy_url

  http_proxy_url=$(get_proxy_url "$PROXY_TYPE" "$PROXY_HOST" "$PROXY_PORT" "$PROXY_USER" "$PROXY_PASS")
  https_proxy_url="$http_proxy_url"
  all_proxy_url="$http_proxy_url"

  for shell_config in ~/.bashrc ~/.zshrc; do
    if [[ -f "$shell_config" ]]; then
      if grep -q '# Proxy settings (auto-generated)' "$shell_config" 2>/dev/null; then
        info "Removing existing proxy settings from $shell_config"
        sed -i '/# Proxy settings (auto-generated)/,/# End proxy settings/d' "$shell_config"
      fi

      info "Adding proxy settings to $shell_config"
      cat >> "$shell_config" << 'SHELL_CONFIG'

 # Proxy settings (auto-generated)
 export http_proxy="HTTP_PROXY_PLACEHOLDER"
 export https_proxy="HTTPS_PROXY_PLACEHOLDER"
 export all_proxy="ALL_PROXY_PLACEHOLDER"
 export no_proxy="NO_PROXY_PLACEHOLDER"
 export HTTP_PROXY="HTTP_PROXY_PLACEHOLDER"
 export HTTPS_PROXY="HTTPS_PROXY_PLACEHOLDER"
 export ALL_PROXY="ALL_PROXY_PLACEHOLDER"
 export NO_PROXY="NO_PROXY_PLACEHOLDER"
 # End proxy settings
SHELL_CONFIG

      sed -i "s|HTTP_PROXY_PLACEHOLDER|${http_proxy_url}|g" "$shell_config"
      sed -i "s|HTTPS_PROXY_PLACEHOLDER|${https_proxy_url}|g" "$shell_config"
      sed -i "s|ALL_PROXY_PLACEHOLDER|${all_proxy_url}|g" "$shell_config"
      sed -i "s|NO_PROXY_PLACEHOLDER|${no_proxy}|g" "$shell_config"

      echo "${green}info: Proxy settings added to $shell_config${reset}"
    fi
  done

  export http_proxy="$http_proxy_url"
  export https_proxy="$https_proxy_url"
  export all_proxy="$all_proxy_url"
  export no_proxy="$no_proxy"
  export HTTP_PROXY="$http_proxy_url"
  export HTTPS_PROXY="$https_proxy_url"
  export ALL_PROXY="$all_proxy_url"
  export NO_PROXY="$no_proxy"

  info "Shell proxy configured successfully"
}

configure_code_server_proxy() {
  echo "${aoi}info: Configuring code-server proxy settings...${reset}"

  local config_dir="${CODE_SERVER_CONFIG_DIR:-~/.config/code-server}"
  local config_file="${config_dir}/config.yaml"
  local proxy_url

  if [[ -f "$config_file" ]]; then
    echo "${aoi}info: Found code-server config at $config_file${reset}"
  else
    echo "${aoi}info: Creating code-server config directory${reset}"
    mkdir -p "$config_dir"
  fi

  if [[ -f "$config_file" ]] && grep -q 'proxy:' "$config_file"; then
    echo "${aoi}info: Removing existing proxy settings from code-server config${reset}"
    sed -i '/^proxy:/d' "$config_file"
  fi

  proxy_url=$(get_proxy_url "$PROXY_TYPE" "$PROXY_HOST" "$PROXY_PORT" "$PROXY_USER" "$PROXY_PASS")

  echo "${aoi}info: Adding proxy settings to code-server config${reset}"
  cat >> "$config_file" << CODE_CONFIG

 proxy: "$proxy_url"
CODE_CONFIG

  echo "${green}info: Code-server proxy configured successfully${reset}"
  echo "${red}warning: ${green}Please restart code-server to apply changes${reset}"
}

configure_docker_proxy() {
  if [[ "$NO_ROOT" -eq '1' ]]; then
    echo "${red}error: ${green}Docker proxy configuration requires root privileges${reset}"
    return 1
  fi

  echo "${aoi}info: Configuring Docker proxy settings...${reset}"

  local docker_config_dir="/etc/systemd/system/docker.service.d"
  local proxy_file="${docker_config_dir}/http-proxy.conf"
  local proxy_url
  local no_proxy="${NO_PROXY:-localhost,127.0.0.1,::1}"

  if [[ ! -d "$docker_config_dir" ]]; then
    mkdir -p "$docker_config_dir"
  fi

  proxy_url=$(get_proxy_url "$PROXY_TYPE" "$PROXY_HOST" "$PROXY_PORT" "$PROXY_USER" "$PROXY_PASS")

  echo "${aoi}info: Creating Docker proxy configuration${reset}"
  cat > "$proxy_file" << DOCKER_CONFIG
 [Service]
 Environment="HTTP_PROXY=$proxy_url"
 Environment="HTTPS_PROXY=$proxy_url"
 Environment="NO_PROXY=$no_proxy"
 Environment="http_proxy=$proxy_url"
 Environment="https_proxy=$proxy_url"
 Environment="no_proxy=$no_proxy"
DOCKER_CONFIG

  echo "${aoi}info: Reloading systemd daemon${reset}"
  if ! systemctl daemon-reload; then
    echo "${red}error: ${green}Failed to reload systemd daemon${reset}"
    return 1
  fi

  echo "${aoi}info: Restarting Docker service${reset}"
  if ! systemctl restart docker; then
    echo "${red}error: ${green}Failed to restart Docker service${reset}"
    return 1
  fi

  echo "${green}info: Docker proxy configured successfully${reset}"
}

show_current_config() {
  echo "${aoi}info: Current proxy configuration:${reset}"
  echo ""
  echo "Environment Variables:"
  echo "  HTTP_PROXY: ${HTTP_PROXY:-not set}"
  echo "  HTTPS_PROXY: ${HTTPS_PROXY:-not set}"
  echo "  ALL_PROXY: ${ALL_PROXY:-not set}"
  echo "  NO_PROXY: ${NO_PROXY:-not set}"
  echo ""
  echo "Shell Config Files:"
  if grep -q 'Proxy settings (auto-generated)' ~/.bashrc 2>/dev/null; then
    echo "  ~/.bashrc: configured"
  else
    echo "  ~/.bashrc: not configured"
  fi
  if [[ -f ~/.zshrc ]]; then
    if grep -q 'Proxy settings (auto-generated)' ~/.zshrc 2>/dev/null; then
      echo "  ~/.zshrc: configured"
    else
      echo "  ~/.zshrc: not configured"
    fi
  fi
  echo ""
  echo "Code-server:"
  local code_config="${CODE_SERVER_CONFIG_DIR:-~/.config/code-server}/config.yaml"
  if [[ -f "$code_config" ]] && grep -q 'proxy:' "$code_config"; then
    echo "  Config: $(grep '^proxy:' "$code_config")"
  else
    echo "  Config: not configured"
  fi
  echo ""
  echo "Docker:"
  if [[ -f "/etc/systemd/system/docker.service.d/http-proxy.conf" ]]; then
    echo "  Proxy configured: yes"
  else
    echo "  Proxy configured: no"
  fi
}

remove_all_configs() {
  echo "${aoi}info: Removing all proxy configurations...${reset}"

  for shell_config in ~/.bashrc ~/.zshrc; do
    if [[ -f "$shell_config" ]] && grep -q '# Proxy settings (auto-generated)' "$shell_config" 2>/dev/null; then
      echo "${aoi}info: Removing proxy settings from $shell_config${reset}"
      sed -i '/# Proxy settings (auto-generated)/,/# End proxy settings/d' "$shell_config"
    fi
  done

  local code_config="${CODE_SERVER_CONFIG_DIR:-~/.config/code-server}/config.yaml"
  if [[ -f "$code_config" ]] && grep -q 'proxy:' "$code_config"; then
    echo "${aoi}info: Removing proxy settings from code-server config${reset}"
    sed -i '/^proxy:/d' "$code_config"
  fi

  if [[ "$NO_ROOT" -ne '1' ]] && [[ -f "/etc/systemd/system/docker.service.d/http-proxy.conf" ]]; then
    echo "${aoi}info: Removing Docker proxy configuration${reset}"
    rm -f "/etc/systemd/system/docker.service.d/http-proxy.conf"
    systemctl daemon-reload
    systemctl restart docker
  fi

  unset http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY

  echo "${green}info: All proxy configurations removed${reset}"
}

judgment_parameters() {
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
      '-h' | '--host')
        PROXY_HOST="${2:?error: Please specify the proxy host.}"
        shift
        ;;
      '-p' | '--port')
        PROXY_PORT="${2:?error: Please specify the proxy port.}"
        shift
        ;;
      '-t' | '--type')
        PROXY_TYPE="${2:?error: Please specify the proxy type (http or socks5).}"
        if [[ "$PROXY_TYPE" != 'http' ]] && [[ "$PROXY_TYPE" != 'socks5' ]]; then
          echo "error: Invalid proxy type. Must be 'http' or 'socks5'."
          exit 1
        fi
        shift
        ;;
      '-u' | '--user')
        PROXY_USER="$2"
        shift
        ;;
      '-w' | '--pass')
        PROXY_PASS="$2"
        shift
        ;;
      '-r' | '--remove')
        REMOVE_CONFIG='1'
        ;;
      '-s' | '--shell-only')
        SHELL_ONLY='1'
        ;;
      '-c' | '--code-only')
        CODE_ONLY='1'
        ;;
      '-d' | '--docker-only')
        DOCKER_ONLY='1'
        ;;
      '--show')
        SHOW_CONFIG='1'
        ;;
      '-H' | '--help')
        HELP='1'
        ;;
      *)
        echo "error: Unknown option: $1"
        echo "Use -H or --help for usage information."
        exit 1
        ;;
    esac
    shift
  done
}

# Install required software
install_software() {
  local package_name="$1"
  local file_to_detect="$2"
  type -P "$file_to_detect" > /dev/null 2>&1 && return
  if [[ -f /etc/debian_version ]]; then
    apt-get -y --no-install-recommends install "$package_name" > /dev/null 2>&1
  elif type -P pacman > /dev/null 2>&1; then
    pacman -Syu --noconfirm --needed "$package_name" > /dev/null 2>&1
  fi
}

main() {
  check_if_running_as_root
  judgment_parameters "$@"
  
  # Validate proxy configuration before proceeding
  validate_proxy_config
  
  # Install required software (tput for colors)
  install_software "ncurses-bin" "tput"
  
  # Set color variables after install
  red=$(tput setaf 1)
  green=$(tput setaf 2)
  aoi=$(tput setaf 6)
  reset=$(tput sgr0)

  [[ "$HELP" -eq '1' ]] && show_help
  [[ "$SHOW_CONFIG" -eq '1' ]] && show_current_config && exit 0
  [[ "$REMOVE_CONFIG" -eq '1' ]] && remove_all_configs && exit 0

  echo "${aoi}info: Configuring proxy settings...${reset}"
  local proxy_display_url
  proxy_display_url=$(get_proxy_url "$PROXY_TYPE" "$PROXY_HOST" "$PROXY_PORT" "$PROXY_USER" "$PROXY_PASS")
  echo "${aoi}info: Proxy: $proxy_display_url${reset}"
  echo ""

  if [[ "$DOCKER_ONLY" -ne '1' ]] && [[ "$CODE_ONLY" -ne '1' ]]; then
    configure_shell_proxy
  fi

  if [[ "$SHELL_ONLY" -ne '1' ]] && [[ "$DOCKER_ONLY" -ne '1' ]]; then
    configure_code_server_proxy
  fi

  if [[ "$SHELL_ONLY" -ne '1' ]] && [[ "$CODE_ONLY" -ne '1' ]] && [[ "$NO_ROOT" -ne '1' ]]; then
    configure_docker_proxy
  fi

  echo ""
  echo "${green}info: Proxy configuration completed!${reset}"
  echo "${aoi}info: Run 'source ~/.bashrc' or start a new terminal to apply shell proxy settings${reset}"
  echo "${aoi}info: Run '$0 --show' to view current configuration${reset}"
}

main "$@"
