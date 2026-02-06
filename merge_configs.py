import json
import yaml
import sys
import os

# 支持的代理类型
PROXY_TYPES = {
    "vless", "vmess", "shadowsocks", "trojan", 
    "hysteria2", "tuic", "wireguard", "hysteria", 
    "shadowsocksr"
}

def convert_clash_to_singbox(proxy):
    name = proxy.get('name')
    ptype = proxy.get('type')
    
    if ptype == 'hysteria2':
        outbound = {
            "type": "hysteria2",
            "tag": name,
            "server": proxy.get('server'),
            "server_port": proxy.get('port'),
            "password": proxy.get('password'),
            "tls": {
                "enabled": True,
                "server_name": proxy.get('sni'),
                "insecure": proxy.get('skip-cert-verify', False)
            }
        }
        if proxy.get('obfs'):
            outbound["obfs"] = {
                "type": proxy.get('obfs'),
                "password": proxy.get('obfs-password')
            }
        return outbound
        
    elif ptype == 'vless':
        outbound = {
            "type": "vless",
            "tag": name,
            "server": proxy.get('server'),
            "server_port": proxy.get('port'),
            "uuid": proxy.get('uuid'),
            "flow": proxy.get('flow', ""),
            "tls": {
                "enabled": proxy.get('tls', False),
                "server_name": proxy.get('servername'),
                "insecure": proxy.get('skip-cert-verify', False),
                "utls": {
                    "enabled": True,
                    "fingerprint": proxy.get('client-fingerprint', 'chrome')
                }
            }
        }
        if proxy.get('reality-opts'):
            outbound["tls"]["reality"] = {
                "enabled": True,
                "public_key": proxy.get('reality-opts').get('public-key'),
                "short_id": proxy.get('reality-opts').get('short-id')
            }
        
        network = proxy.get('network')
        if network == 'grpc':
            outbound["transport"] = {
                "type": "grpc",
                "service_name": proxy.get('grpc-opts', {}).get('grpc-service-name', 'grpc')
            }
        elif network == 'ws':
             outbound["transport"] = {
                "type": "ws",
                "path": proxy.get('ws-opts', {}).get('path', '/'),
                "headers": proxy.get('ws-opts', {}).get('headers', {})
            }
        return outbound
    
    elif ptype == 'shadowsocks':
        return {
            "type": "shadowsocks",
            "tag": name,
            "server": proxy.get('server'),
            "server_port": proxy.get('port'),
            "method": proxy.get('cipher'),
            "password": proxy.get('password')
        }
    
    elif ptype == 'trojan':
        return {
            "type": "trojan",
            "tag": name,
            "server": proxy.get('server'),
            "server_port": proxy.get('port'),
            "password": proxy.get('password'),
            "tls": {
                "enabled": True,
                "server_name": proxy.get('sni') or proxy.get('servername'),
                "insecure": proxy.get('skip-cert-verify', False)
            }
        }

    return None

def main():
    sb_path = sys.argv[1] if len(sys.argv) > 1 else "/etc/sing-box/config.json"
    clash_path = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml")
    output_path = sys.argv[3] if len(sys.argv) > 3 else "optimized_singbox_config.json"
    
    # 环境测试路径自动校准
    if not os.path.exists(sb_path) and os.path.exists("./config.json") and sb_path == "/etc/sing-box/config.json":
        sb_path = "./config.json"
    if not os.path.exists(sb_path) and os.path.exists("./singbox_client_config.json") and sb_path == "/etc/sing-box/config.json":
        sb_path = "./singbox_client_config.json"
    
    if not os.path.exists(clash_path) and os.path.exists("./clash-verge.yaml"):
        clash_path = "./clash-verge.yaml"
    if not os.path.exists(clash_path) and os.path.exists(os.path.expanduser("~/clash-verge.yaml")):
        clash_path = os.path.expanduser("~/clash-verge.yaml")

    if not os.path.exists(sb_path):
        print(f"Error: Sing-box config not found at {sb_path}")
        sys.exit(1)
    if not os.path.exists(clash_path):
        print(f"Error: Clash config not found at {clash_path}")
        sys.exit(1)

    print(f"[*] Reading Sing-box config: {sb_path}")
    print(f"[*] Reading Clash config: {clash_path}")

    with open(sb_path, 'r') as f:
        sb_config = json.load(f)
    
    with open(clash_path, 'r') as f:
        clash_config = yaml.safe_load(f)
    
    # 分类 Sing-box 原有的 outbounds
    old_outbounds = sb_config.get('outbounds', [])
    non_proxy_outbounds = [] # direct, dns 等
    original_proxies = {}   # tag -> config
    
    # 按照在原配置中的出现顺序记录
    for o in old_outbounds:
        tag = o.get('tag')
        if o.get('type') in PROXY_TYPES:
            original_proxies[tag] = o
        elif tag not in ["Clash-Auto", "Auto-Select-All"]:
            non_proxy_outbounds.append(o)
    
    # 转换 Clash 代理节点
    clash_proxies = clash_config.get('proxies', [])
    new_clash_outbounds = []
    new_clash_tags = []
    
    for p in clash_proxies:
        sb_out = convert_clash_to_singbox(p)
        if sb_out:
            tag = sb_out['tag']
            # 如果存在同名节点，则从原有代理池中移除（标记为已由 Clash 替换）
            if tag in original_proxies:
                print(f"[*] Overwriting existing proxy: {tag}")
                del original_proxies[tag]
            
            new_clash_outbounds.append(sb_out)
            new_clash_tags.append(tag)
    
    # 剩余的 original_proxies 就是没被 Clash 替换的 SB 节点
    remaining_sb_proxies = list(original_proxies.values())
    remaining_sb_tags = [o.get('tag') for o in remaining_sb_proxies]
    
    # 构建最终的 outbounds 列表
    # 顺序：基础出站 (direct等) -> Clash 节点 -> Sing-box 剩余节点 -> 策略组
    final_outbounds = non_proxy_outbounds + new_clash_outbounds + remaining_sb_proxies
    
    all_proxy_tags = new_clash_tags + remaining_sb_tags
    
    if not all_proxy_tags:
        print("Warning: No proxy nodes found.")
    else:
        # 创建自动选择组
        urltest_group = {
            "type": "urltest",
            "tag": "Auto-Select-All",
            "outbounds": all_proxy_tags,
            "url": "http://www.gstatic.com/generate_204",
            "interval": "3m",
            "tolerance": 50
        }
        final_outbounds.append(urltest_group)
        
        # 强制将 final 路由指向这个组（逻辑优化：如果存在 final 路由）
        if "route" in sb_config:
            sb_config["route"]["final"] = "Auto-Select-All"

    sb_config["outbounds"] = final_outbounds

    with open(output_path, 'w') as f:
        json.dump(sb_config, f, indent=2, ensure_ascii=False)
    
    print(f"[+] Successfully merged/replaced proxies.")
    print(f"[+] Combined group 'Auto-Select-All' contains {len(all_proxy_tags)} nodes.")
    print(f"[+] Saved to: {output_path}")

if __name__ == "__main__":
    main()
