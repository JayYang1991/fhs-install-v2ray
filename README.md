# fhs-install-v2ray

> Bash script for installing V2Ray in operating systems such as Debian / CentOS / Fedora / openSUSE that support systemd

该脚本安装的文件符合 [Filesystem Hierarchy Standard (FHS)](https://en.wikipedia.org/wiki/Filesystem_Hierarchy_Standard)：

```
installed: /usr/local/bin/v2ray
installed: /usr/local/bin/v2ctl
installed: /usr/local/share/v2ray/geoip.dat
installed: /usr/local/share/v2ray/geosite.dat
installed: /usr/local/etc/v2ray/config.json
installed: /var/log/v2ray/
installed: /var/log/v2ray/access.log
installed: /var/log/v2ray/error.log
installed: /etc/systemd/system/v2ray.service
installed: /etc/systemd/system/v2ray@.service
```

## 项目介绍

本项目基于 [V2Fly 官方 fhs-install-v2ray](https://github.com/v2fly/fhs-install-v2ray) 项目，在标准安装功能的基础上，扩展了以下实用功能：

- **统一安装脚本** - 一个脚本支持多种安装模式，通过 `--mode` 参数选择
- **代理服务端安装** - 快速部署 V2Ray 代理服务器
- **代理客户端安装** - 配置客户端通过代理服务器访问网络
- **反向代理服务端安装** - 实现内网服务穿透，从外网访问局域网服务
- **Vultr 自动化部署** - 一键创建云服务器并自动安装配置 V2Ray
- **预置配置模板** - 提供常用场景的配置文件模板

## 重要提示

**不推荐在 docker 中使用本项目安装 v2ray，请直接使用 [官方镜像](https://github.com/v2fly/docker)。**  
如果官方镜像不能满足您自定义安装的需要，请以**复刻并修改上游 dockerfile 的方式来实现**。

本项目**不会为您自动生成配置文件**；**只解决用户安装阶段遇到的问题**。其他问题在这里是无法得到帮助的。  
请在安装完成后参阅 [文档](https://www.v2fly.org/) 了解配置文件语法，并自己完成适合自己的配置文件。过程中可参阅社区贡献的 [配置文件模板](https://github.com/v2fly/v2ray-examples)  
（**提请您注意这些模板复制下来以后是需要您自己修改调整的，不能直接使用**）

## 支持的操作系统

- Debian 8+ / Ubuntu 16.04+
- CentOS 7+ / Rocky Linux / AlmaLinux
- Fedora 28+
- openSUSE 15+
- Arch Linux

## 使用说明

* 该脚本在运行时会提供 `info` 和 `error` 等信息，请仔细阅读。

### configure-proxy.sh - 代理配置脚本

`configure-proxy.sh` 是一个用于配置终端代理环境的脚本，支持多种应用代理设置，包括 Shell、Code-server 和 Docker。

#### 基本用法

```bash
# 使用默认设置配置所有代理 (socks5代理，127.0.0.1:7897)
./configure-proxy.sh

# 显示帮助信息
./configure-proxy.sh -H
./configure-proxy.sh --help
```

#### 自定义配置

```bash
# 配置HTTP代理
./configure-proxy.sh -h 192.168.1.100 -p 8080 -t http

# 配置带认证的代理
./configure-proxy.sh -h proxy.example.com -p 3128 -u username -w password

# 自定义不代理列表
./configure-proxy.sh -n localhost,127.0.0.1,::1,docker-registry
```

#### 选择性配置

```bash
# 仅配置 Shell 代理
./configure-proxy.sh -s
./configure-proxy.sh --shell-only

# 仅配置 Code-server 代理
./configure-proxy.sh -c
./configure-proxy.sh --code-only

# 仅配置 Docker 代理
./configure-proxy.sh -d
./configure-proxy.sh --docker-only
```

#### 管理配置

```bash
# 显示当前代理配置
./configure-proxy.sh --show

# 移除所有代理配置
./configure-proxy.sh -r
./configure-proxy.sh --remove
```

#### 环境变量

可以在运行脚本前设置以下环境变量：

```bash
export PROXY_HOST='127.0.0.1'        # 代理主机 (默认: 127.0.0.1)
export PROXY_PORT='7897'            # 代理端口 (默认: 7897)
export PROXY_TYPE='socks5'          # 代理类型: http 或 socks5 (默认: socks5)
export PROXY_USER='username'        # 代理用户名 (可选)
export PROXY_PASS='password'        # 代理密码 (可选)
export NO_PROXY='localhost,127.0.0.1,::1'  # 不代理列表 (可选)
```

#### 参数说明

| 参数 | 简写 | 描述 | 默认值 |
|------|------|------|--------|
| `--host` | `-h` | 代理主机地址 | 127.0.0.1 |
| `--port` | `-p` | 代理端口 | 7897 |
| `--type` | `-t` | 代理类型 (http/socks5) | socks5 |
| `--user` | `-u` | 代理用户名 | (空) |
| `--pass` | `-w` | 代理密码 | (空) |
| `--no-proxy` | `-n` | 不代理列表 | localhost,127.0.0.1,::1 |
| `--remove` | `-r` | 移除所有配置 | - |
| `--shell-only` | `-s` | 仅配置 Shell | - |
| `--code-only` | `-c` | 仅配置 Code-server | - |
| `--docker-only` | `-d` | 仅配置 Docker | - |
| `--show` | - | 显示当前配置 | - |
| `--help` | `-H` | 显示帮助信息 | - |

#### 配置详情

##### Shell 代理配置

脚本会在 `~/.bashrc` 和 `~/.zshrc` 中添加以下环境变量：

```bash
export http_proxy="http://127.0.0.1:7897"
export https_proxy="http://127.0.0.1:7897" 
export all_proxy="http://127.0.0.1:7897"
export no_proxy="localhost,127.0.0.1,::1"
export HTTP_PROXY="http://127.0.0.1:7897"
export HTTPS_PROXY="http://127.0.0.1:7897"
export ALL_PROXY="http://127.0.0.1:7897" 
export NO_PROXY="localhost,127.0.0.1,::1"
```

##### Code-server 配置

在 `~/.config/code-server/config.yaml` 中添加：

```yaml
proxy: "http://127.0.0.1:7897"
```

##### Docker 配置

在 `/etc/systemd/system/docker.service.d/http-proxy.conf` 中添加：

```ini
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:7897"
Environment="HTTPS_PROXY=http://127.0.0.1:7897"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
Environment="http_proxy=http://127.0.0.1:7897"
Environment="https_proxy=http://127.0.0.1:7897" 
Environment="no_proxy=localhost,127.0.0.1,::1"
```

#### 注意事项

1. **权限要求**：Docker 配置需要 root 权限
2. **Code-server 重启**：配置 Code-server 后需要重启服务才能生效
3. **Shell 配置**：Shell 配置需要重新加载配置文件或新开终端才能生效
4. **验证配置**：使用 `./configure-proxy.sh --show` 查看当前配置状态
5. **清理配置**：使用 `./configure-proxy.sh --remove` 移除所有配置

#### 故障排除

##### 常见问题

1. **权限不足**：Docker 配置需要 root 权限，脚本会提示并询问是否继续
2. **配置不生效**：需要重新加载 shell 配置或重启相关服务
3. **代理连接失败**：检查代理服务器是否正常运行，端口是否正确

##### 调试模式

设置 `DEBUG=1` 环境变量可启用调试输出：

```bash
export DEBUG=1
./configure-proxy.sh
```

#### 示例

##### 完整配置示例

```bash
# 设置环境变量
export PROXY_HOST='proxy.example.com'
export PROXY_PORT='3128'
export PROXY_TYPE='http'
export PROXY_USER='myuser'
export PROXY_PASS='mypassword'
export NO_PROXY='localhost,127.0.0.1,::1,192.168.1.0/24'

# 执行配置
sudo ./configure-proxy.sh
```

##### 仅配置 Docker 代理

```bash
sudo ./configure-proxy.sh -d
```

##### 查看当前配置

```bash
./configure-proxy.sh --show
```

##### 移除所有配置

```bash
sudo ./configure-proxy.sh --remove
```

### install-singbox-server.sh - sing-box Reality 服务器安装脚本

`install-singbox-server.sh` 用于在 Linux 服务器上快速部署基于 VLESS + Reality + Vision 协议的 sing-box 服务器。

#### 基本用法

```bash
# 一键安装（使用默认参数）
bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-singbox-server.sh)
```

#### 参数说明

可以通过环境变量或命令行参数自定义配置：

| 参数 | 环境变量 | 描述 | 默认值 |
|------|----------|------|--------|
| `--port` | `PORT` | 监听端口 | 443 |
| `--domain` | `DOMAIN` | SNI 域名 (Reality 目标) | www.cloudflare.com |
| `--uuid` | `UUID` | 用户 UUID | 自动生成 |
| `--short-id` | `SHORT_ID` | Reality Short ID | 自动生成 |
| `--log-level` | `LOG_LEVEL` | 日志级别 | info |

#### 示例

```bash
# 自定义端口和域名
bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-singbox-server.sh) --port 8443 --domain google.com
```

#### 特性

1. **全自动部署**：自动安装架构匹配的 sing-box 与依赖。
2. **Reality 安全保障**：自动生成密钥对并配置 Reality 隧道。
3. **防火墙自动配置**：支持 `ufw` 和 `firewalld` 自动放行端口。
4. **多格式导出**：
    - 通用 **VLESS 链接**。
    - **Clash Verge 导入链接** (clash://)。
    - **Clash Verge (Mihomo) 配置文件正文**。
    - 详细的客户端手动配置参数。

### 统一安装脚本

本项目已将所有安装脚本合并为一个统一脚本 `install-v2ray.sh`，通过 `--mode` 参数选择不同的安装模式。

```bash
# 使用统一脚本安装
# bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray.sh) --mode <mode>
```

#### 安装 V2Ray 代理服务端

**环境变量设置**（必须）：
- `V2RAY_PROXY_ID`: VMess 用户 ID

```bash
# 设置环境变量
export V2RAY_PROXY_ID="your-vmess-id"

# 安装代理服务端
# bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray.sh) --mode proxy-server
```

**特性**：
- 使用 VMess 协议，KCP 传输方式
- 内置流量统计功能（通过 API）
- 支持域名路由规则，可自定义分流策略
- 预置常用域名黑名单

### 更新 geoip.dat 和 geosite.dat

可以使用统一脚本仅更新数据文件：

```bash
# 更新 .dat 数据文件
bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray.sh) --mode update-dat
```

### 移除 V2Ray

```bash
# 移除 V2Ray（所有模式）
# bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray.sh) --remove
```

#### 安装 V2Ray Proxy 客户端

在本地机器上安装客户端，通过代理服务器访问网络。

**环境变量设置**（必须）：
- `V2RAY_PROXY_SERVER_IP`: 代理服务器 IP 地址
- `V2RAY_PROXY_ID`: VMess 用户 ID
- `V2RAY_REVERSE_SERVER_IP`: 反向代理服务器 IP 地址（可选）
- `V2RAY_REVERSE_ID`: 反向代理用户 ID（可选）

```bash
# 设置环境变量
export V2RAY_PROXY_SERVER_IP="your-server-ip"
export V2RAY_PROXY_ID="your-vmess-id"
export V2RAY_REVERSE_SERVER_IP="your-reverse-server-ip"
export V2RAY_REVERSE_ID="your-reverse-id"

# 安装客户端
# bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray.sh) --mode proxy-client
```

**特性**：
- 支持 SOCKS5 和 HTTP 代理协议
- 内置流量健康检测和自动故障切换
- 支持多出口负载均衡
- 预置国内直连规则（geosite:cn）

#### 安装 V2Ray 反向代理服务端

实现内网穿透，从外网访问局域网内的服务。

**环境变量设置**（必须）：
- `V2RAY_REVERSE_ID`: 反向代理用户 ID

```bash
# 设置环境变量
export V2RAY_REVERSE_ID="your-reverse-id"

# 安装反向代理服务端
# bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray.sh) --mode reverse-server
```

**特性**：
- 支持多域名反向代理
- 使用 VMess 协议建立隧道
- 基于 SNI 路由，支持 HTTPS 流量转发

**注意事项**：
- 在安装 V2Ray 客户端的节点需要配置需要反向代理的域名解析到局域网 IP
- 否则会导致报文循环处理

### 流量统计命令

```bash
# v2ray api stats --server="127.0.0.1:10085"
```

## Vultr 自动化部署

本项目提供了 Vultr 云服务器自动化部署脚本，可一键创建服务器并自动安装 V2Ray 代理服务端。

### 前置条件

- 安装 [vultr-cli](https://github.com/vultr/vultr-cli) 工具
- 配置 Vultr API Key
- 准备 SSH 密钥
- 安装 Python 3 及其 YAML 解析库 (用于 `--update-clash`): `sudo apt install python3 python3-yaml`

### 使用方法

```bash
# 查看帮助
# ./create_vultr_instance.sh --help

# 创建实例并安装 V2Ray/sing-box（默认不更新本地配置）
# ./create_vultr_instance.sh

# 创建实例并自动更新本地 V2Ray 客户端配置
# ./create_vultr_instance.sh --update-local

# 创建实例并自动更新本地 Clash 配置文件 (针对 Clash Verge Rev/Mihomo)
# ./create_vultr_instance.sh --update-clash --clash-config-path /path/to/vultr-private.yaml
```

**脚本功能**：
- 自动检测并安装依赖 (`vultr-cli`, `curl` 等)
- 自动创建 Vultr 实例（默认配置：Ubuntu 24.04，1核 0.5GB）
- 支持 IPv4 和 IPv6 地址自动提取
- 等待实例启动并检测 SSH 连接（严格校验 root 登录及稳定性）
- 自动在远程服务器安装 **V2Ray** 和 **sing-box** (含 Reality 配置)
- **参数自动捕获**：自动从远程提取生成的 UUID、Reality 公钥和 Short ID
- **本地 Clash 配置更新**：
    - 自动将新节点添加到指定 YAML 配置文件
    - **服务同步**：自动将更新后的配置同步到 `mihomo-service.yaml`
    - **自动重启**：更新完成后自动重启本地 `verge-mihomo.service`
- （可选）自动更新本地 V2Ray 客户端配置并重启服务

**自定义配置**：
可以通过设置环境变量或命令行参数修改以下变量：
- `VULTR_REGION`: 数据中心区域（默认：ewr）
- `VULTR_PLAN`: 实例规格（默认：vc2-1c-0.5gb-v6）
- `VULTR_OS`: 操作系统 ID（默认：2288，Ubuntu 24.04）
- `VULTR_HOST`: 实例主机名（默认：jayyang）
- `VULTR_LABEL`: 实例标签（默认：ubuntu_2404）
- `VULTR_TAG`: 实例标签（TAG）（默认：v2ray）
- `VULTR_SSH_KEYS`: SSH 密钥 ID 列表（逗号分隔）
- `VULTR_SCRIPT_ID`: 启动脚本 ID
- `V2RAY_REPO_BRANCH`: 脚本仓库分支（默认：master）
- `ENABLE_LOCAL_CONFIG`: 设置为 `true` 以启用 V2Ray 本地配置更新（等同于 `-u` 参数）
- `ENABLE_CLASH_CONFIG`: 设置为 `true` 以启用 Clash 配置更新（等同于 `-c` 参数）
- `CLASH_CONFIG_PATH`: 本地 Clash 配置文件路径
- `SINGBOX_PORT`: sing-box 监听端口（默认：443）
- `SINGBOX_DOMAIN`: sing-box SNI 域名 (Reality 目标)（默认：www.cloudflare.com）
- `SINGBOX_UUID`: sing-box 用户 UUID
- `SINGBOX_SHORT_ID`: sing-box Reality Short ID
- `SINGBOX_LOG_LEVEL`: sing-box 日志级别

### 删除实例

```bash
# ./remove_vultr_instance.sh
```

## 安装标准版 V2Ray

```bash
// 安装标准版 V2Ray（默认模式）
# bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray.sh)
```

## 安装特定版本的 V2Ray

```bash
// 安装指定版本的 V2Ray
# bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray.sh) --version v4.18.0
```

## 检查 V2Ray 更新

```bash
// 检查是否有新版本
# bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray.sh) -c
```

## 强制安装最新版 V2Ray

```bash
// 强制安装最新版本（即使已经是最新）
# bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray.sh) -f
```

## 从本地文件安装 V2Ray

```bash
// 从本地文件安装 V2Ray
# bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray.sh) -l /path/to/v2ray.zip
```

## 使用代理服务器下载

```bash
// 通过代理服务器下载
# bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray.sh) -p http://127.0.0.1:8118
```

## 安装 V2Ray 的帮助信息

```bash
// 查看安装脚本的帮助信息
# bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray.sh) --help
```

## 配置文件模板

项目提供了多种配置文件模板，位于项目根目录：

| 文件名 | 用途 |
|--------|------|
| `proxy_server_config.json` | 代理服务端配置 |
| `proxy_client_config.json` | 代理客户端配置 |
| `reverse_server_config.json` | 反向代理服务端配置 |
| `reverse_client_config.json` | 反向代理客户端配置 |
| `server_config.json` | 通用服务器配置 |

**使用方法**：
1. 下载对应的配置文件模板
2. 替换占位符（如 `{V2RAY_PROXY_ID}`、`{V2RAY_PROXY_SERVER_IP}` 等）
3. 复制到 `/usr/local/etc/v2ray/config.json`
4. 重启 V2Ray 服务：`systemctl restart v2ray.service`

## 常用命令

```bash
# 启动 V2Ray 服务
# systemctl start v2ray.service

# 停止 V2Ray 服务
# systemctl stop v2ray.service

# 重启 V2Ray 服务
# systemctl restart v2ray.service

# 查看 V2Ray 服务状态
# systemctl status v2ray.service

# 查看 V2Ray 日志
# journalctl -u v2ray.service -f

# 查看配置文件
# cat /usr/local/etc/v2ray/config.json

# 测试配置文件
# v2ray -test -config /usr/local/etc/v2ray/config.json
```

## 环境变量

### 通用路径变量

```bash
# 设置数据文件路径（默认：/usr/local/share/v2ray）
export DAT_PATH='/usr/local/share/v2ray'

# 设置配置文件路径（默认：/usr/local/etc/v2ray）
export JSON_PATH='/usr/local/etc/v2ray'

# 设置多配置文件路径（可选）
export JSONS_PATH='/usr/local/etc/v2ray'

# 检查所有服务文件（可选，默认：no）
export check_all_service_files='yes'
```

### 代理服务端变量

```bash
# 代理服务器 IP（客户端配置时使用）
export V2RAY_PROXY_SERVER_IP="your-server-ip"

# VMess 用户 ID
export V2RAY_PROXY_ID="your-vmess-id"
```

### 反向代理变量

```bash
# 反向代理服务器 IP
export V2RAY_REVERSE_SERVER_IP="your-reverse-server-ip"

# 反向代理用户 ID
export V2RAY_REVERSE_ID="your-reverse-id"
```

## 解决问题

* 「[不安装或更新 geoip.dat 和 geosite.dat](https://github.com/v2fly/fhs-install-v2ray/wiki/Do-not-install-or-update-geoip.dat-and-geosite-dat-zh-Hans-CN)」。
* 「[使用证书时权限不足](https://github.com/v2fly/fhs-install-v2ray/wiki/Insufficient-permissions-when-using-certificates-zh-Hans-CN)」。
* 「[从旧脚本迁移至此](https://github.com/v2fly/fhs-install-v2ray/wiki/Migrate-from-the-old-script-to-this-zh-Hans-CN)」。
* 「[将 .dat 文档由 lib 目录移动到 share 目录](https://github.com/v2fly/fhs-install-v2ray/wiki/Move-.dat-files-from-lib-directory-to-share-directory-zh-Hans-CN)」。
* 「[使用 VLESS 协议](https://github.com/v2fly/fhs-install-v2ray/wiki/To-use-the-VLESS-protocol-zh-Hans-CN)」。

> 若您的问题没有在上方列出，欢迎在 Issue 区提出。

**提问前请先阅读 [Issue #63](https://github.com/v2fly/fhs-install-v2ray/issues/63)，否则可能无法得到解答并被锁定。**

## 开发与测试

### Linting

```bash
# 使用 shellcheck 检查脚本
shellcheck install-*.sh

# 使用 shfmt 格式化脚本
shfmt -i 2 -ci -sr -w install-*.sh
```

### 测试

可以直接运行脚本进行测试。CI 通过 `.github/workflows/sh-checker.yml` 在 Ubuntu、Rocky Linux 和 Arch Linux 上自动运行测试。

## 贡献

请于 [develop](https://github.com/JayYang1991/fhs-install-v2ray/tree/develop) 分支进行，以避免对主分支造成破坏。

待确定无误后，两分支将进行合并。

## 代码风格

- Shebang: `#!/usr/bin/env bash`
- 缩进：2 个空格
- 使用双引号包裹所有变量引用：`"$VARIABLE"`
- 使用 `[[ ]]` 而非 `[ ]` 进行测试
- 函数命名：snake_case
- 常量命名：UPPER_CASE

详见 [AGENTS.md](AGENTS.md)。

## 许可证

本项目基于 [V2Fly 官方项目](https://github.com/v2fly/fhs-install-v2ray) fork，遵循相同的许可证（GPL-3.0 或更高版本）。

## 相关链接

- [V2Fly 官方文档](https://www.v2fly.org/)
- [V2Ray 配置示例](https://github.com/v2fly/v2ray-examples)
- [V2Fly 官方 Docker 镜像](https://github.com/v2fly/docker)
- [V2Fly fhs-install-v2ray](https://github.com/v2fly/fhs-install-v2ray)
