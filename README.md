# fhs-install-v2ray

> Bash scripts for installing V2Ray and sing-box on systemd-based Linux distributions

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

本项目基于 [V2Fly 官方 fhs-install-v2ray](https://github.com/v2fly/fhs-install-v2ray) 项目，在标准安装功能的基础上，扩展了以下功能：

- **统一安装脚本** - 一个脚本支持多种安装模式，通过 `--mode` 参数选择
- **代理服务端安装** - 快速部署 V2Ray 代理服务器
- **代理客户端安装** - 配置客户端通过代理服务器访问网络
- **反向代理服务端安装** - 实现内网服务穿透，从外网访问局域网服务
- **Vultr 自动化部署** - 一键创建云服务器并自动安装配置 sing-box
- **预置配置模板** - 提供常用场景的配置文件模板（V2Ray 与 sing-box）

## 配置模板说明

本仓库包含多套可直接修改使用的配置模板（均含占位符）：

- `proxy_server_config.json` / `proxy_client_config.json`：V2Ray 代理模板（gRPC 传输）。
- `reverse_server_config.json`：V2Ray 反向代理服务端模板。
- `singbox_server_config.json`：sing-box Reality 服务端模板（VLESS + Reality）。
- `singbox_client_config.json`：sing-box 客户端模板（TUN 模式，局域网与中国地址直连，其余走代理）。

sing-box 模板占位符以 `SINGBOX_*` 命名，例如 `{SINGBOX_SERVER_IP}`、`{SINGBOX_UUID}`。

## 重要提示

**不推荐在 docker 中使用本项目安装 v2ray，请直接使用 [官方镜像](https://github.com/v2fly/docker)。**  
如果官方镜像不能满足您自定义安装的需要，请以**复刻并修改上游 dockerfile 的方式来实现**。

V2Ray 安装**不会自动生成配置文件**；sing-box 安装脚本会基于模板生成配置。  
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

### install-singbox-server.sh - sing-box Reality 服务器安装脚本

`install-singbox-server.sh` 用于在 Linux 服务器上快速部署基于 VLESS + Reality + Vision 协议的 sing-box 服务器。

#### 基本用法

```bash
# 一键安装（使用默认参数）
bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-singbox-server.sh)
```

安装完成后会在服务端生成：
- `/etc/sing-box/config.json`
- `/etc/sing-box/client_config.json`（客户端配置，脚本会输出该路径）

#### 参数说明

可以通过环境变量或命令行参数自定义配置：

| 参数 | 环境变量 | 描述 | 默认值 |
|------|----------|------|--------|
| `--port` | `SINGBOX_PORT` | 监听端口 | 443 |
| `--domain` | `SINGBOX_DOMAIN` | SNI 域名 (Reality 目标) | www.cloudflare.com |
| `--uuid` | `SINGBOX_UUID` | 用户 UUID | 自动生成 |
| `--short-id` | `SINGBOX_SHORT_ID` | Reality Short ID | 自动生成 |
| `--log-level` | `SINGBOX_LOG_LEVEL` | 日志级别 | info |

#### 示例

```bash
# 自定义端口和域名
bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-singbox-server.sh) --port 8443 --domain google.com
```

#### 特性

1. **全自动部署**：自动安装架构匹配的 sing-box 与依赖。
2. **Reality 安全保障**：自动生成密钥对并配置 Reality 隧道。
3. **防火墙自动配置**：支持 `ufw` 和 `firewalld` 自动放行端口。
4. **配置生成**：在线下载模板并生成 `/etc/sing-box/config.json` 与 `/etc/sing-box/client_config.json`，并输出客户端配置路径。

### 统一安装脚本

V2Ray 相关安装统一由 `install-v2ray.sh` 处理，通过 `--mode` 参数选择不同的安装模式（`proxy-server` / `proxy-client` / `reverse-server` / `update-dat` / `--remove`）。

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
- 使用 VMess 协议与 gRPC 传输
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

### 流量统计命令

```bash
# v2ray api stats --server="127.0.0.1:10085"
```

## Vultr 自动化部署

本项目提供了 Vultr 云服务器自动化部署脚本，可一键创建服务器并自动安装 sing-box（Reality）。

### 前置条件

- 安装 [vultr-cli](https://github.com/vultr/vultr-cli) 工具
- 配置 Vultr API Key
- 准备 SSH 密钥

### 使用方法

```bash
# 查看帮助
# ./create_vultr_instance.sh --help

# 创建实例并安装 sing-box
# ./create_vultr_instance.sh
```

**脚本功能**：
- 自动检测并安装依赖 (`vultr-cli`, `curl` 等)
- 自动创建 Vultr 实例（默认配置：Ubuntu 24.04，1核 0.5GB）
- 支持 IPv4 和 IPv6 地址自动提取
- 等待实例启动并检测 SSH 连接（严格校验 root 登录及稳定性）
- 自动在远程服务器安装 **sing-box** (含 Reality 配置)
- 自动从远端客户端配置中提取 UUID、Reality 公钥和 Short ID

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

## 配置工具

本仓库提供了两个强大的配置处理工具：

#### 1. `merge_configs.py` (Clash -> Sing-box)
该工具用于将外部 Clash 节点的代理信息合并到现有的 Sing-box 配置文件中。

`merge_configs.py` 是一个 Python 脚本，支持将 Clash Verge (Mihomo) 导出的 YAML 配置文件中的节点转换为 sing-box 格式，并与现有的 sing-box 节点合并。

#### 主要功能
- **全节点合并**：自动提取并在 sing-box 中保留原有节点，同时加入 Clash 节点。
- **智能策略组**：自动创建一个名为 `Auto-Select-All` 的 `urltest` 组，包含所有合并的节点，实现毫秒级自动优选。
- **协议支持**：支持 VLESS (Reality/gRPC/WS)、Hysteria2、Shadowsocks、Trojan 等主流协议转换。
- **智能合并与去重**：如果 Clash 配置文件中的节点名称与 Sing-box 现有节点冲突，脚本将强制使用 Clash 的配置覆盖原有节点，避免重复。
- **灵活排序**：默认将所有代理节点合并至 `Auto-Select-All` 组，Clash 节点排在前面，Sing-box 原始节点排在最后。
- **自定义输出**：支持指定输出文件路径。

#### 使用方法
```bash
# 确保已安装 PyYAML 库
# pip install PyYAML

python3 merge_configs.py <singbox_json_path> <clash_yaml_path> <output_path>
```

#### 2. `sb_to_clash.py` (Sing-box -> Clash)
该工具用于将现有的 Sing-box 配置文件转换为 Clash Verge (Mihomo) 格式。

**特性：**
- **协议转换**：支持将 VLESS (Reality/gRPC/WS)、Hysteria2、Shadowsocks、Trojan 从 Sing-box 格式转换为 Clash 格式。
- **自动模板**：自动生成完整的 Clash 配置文件，包含优化的 DNS 设置、策略组（手动选择、自动优选）以及常用路由规则。
- **自定义路径**：支持指定输入 Sing-box 路径和输出 YAML 路径。

**使用方法：**
```bash
# 默认转换 (输入 /etc/sing-box/config.json, 输出当前目录 clash_config.yaml)
python3 sb_to_clash.py

# 自定义路径
python3 sb_to_clash.py /path/to/singbox.json /path/to/output.yaml
```

#### 示例
```bash
python3 merge_configs.py /etc/sing-box/config.json ~/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml final_config.json
```

## 配置文件模板

项目提供了多种配置文件模板，位于项目根目录：

| 文件名 | 用途 |
|--------|------|
| `proxy_server_config.json` | V2Ray 代理服务端配置 |
| `proxy_client_config.json` | V2Ray 代理客户端配置 |
| `reverse_server_config.json` | V2Ray 反向代理服务端配置 |
| `singbox_server_config.json` | sing-box Reality 服务端模板 |
| `singbox_client_config.json` | sing-box 客户端模板 |

**使用方法（V2Ray）**：
1. 下载对应的配置文件模板
2. 替换占位符（如 `{V2RAY_PROXY_ID}`、`{V2RAY_PROXY_SERVER_IP}` 等）
3. 复制到 `/usr/local/etc/v2ray/config.json`
4. 重启 V2Ray 服务：`systemctl restart v2ray.service`

**使用方法（sing-box）**：
1. 直接运行 `install-singbox-server.sh`，脚本会在线下载模板并生成 `/etc/sing-box/config.json`
2. 客户端模板生成后的文件为 `/etc/sing-box/client_config.json`

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
