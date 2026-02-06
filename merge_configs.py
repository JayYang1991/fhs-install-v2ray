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
    
    # 自动重定向环境测试路径
    if not os.path.exists(sb_path) and os.path.exists("./config.json") and sb_path == "/etc/sing-box/config.json":
        sb_path = "./config.json"
    
    if not os.path.exists(clash_path) and os.path.exists("./clash-verge.yaml") and "clash-verge.yaml" in clash_path:
        clash_path = "./clash-verge.yaml"

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
    
    # 提取 Sing-box 原有的代理节点
    existing_outbounds = sb_config.get('outbounds', [])
    existing_proxy_tags = [o.get('tag') for o in existing_outbounds if o.get('type') in PROXY_TYPES]
    
    # 转换 Clash 代理节点
    clash_proxies = clash_config.get('proxies', [])
    new_clash_outbounds = []
    new_clash_tags = []
    
    # 记录已使用的 tag，防止重复
    all_used_tags = {o.get('tag') for o in existing_outbounds}
    
    for p in clash_proxies:
        sb_out = convert_clash_to_singbox(p)
        if sb_out:
            tag = sb_out['tag']
            if tag in all_used_tags:
                tag = f"{tag}-clash"
                sb_out['tag'] = tag
            
            new_clash_outbounds.append(sb_out)
            new_clash_tags.append(tag)
            all_used_tags.add(tag)
    
    # 合并所有代理节点到一个列表 (Clash 节点在前，Sing-box 原有节点在后)
    all_proxy_tags = new_clash_tags + existing_proxy_tags
    
    if not all_proxy_tags:
        print("Warning: No proxy nodes found in either config.")
    else:
        # 创建统一的自动选择组
        urltest_group = {
            "type": "urltest",
            "tag": "Auto-Select-All",
            "outbounds": all_proxy_tags,
            "url": "http://www.gstatic.com/generate_204",
            "interval": "3m",
            "tolerance": 50
        }
        
        # 清理旧的自动选择组（如果有）
        sb_config["outbounds"] = [o for o in existing_outbounds if o.get('tag') != "Clash-Auto" and o.get('tag') != "Auto-Select-All"]
        
        # 添加新节点和组
        sb_config["outbounds"].extend(new_clash_outbounds)
        sb_config["outbounds"].append(urltest_group)
        
        # 更新路由规则的默认出口（可选，这里保持灵活，不强制修改 final，但通常用户希望最终指向这个组）
        # 如果需要自动修改 final 出口，可以取消下面注释：
        # if "route" in sb_config and "final" in sb_config["route"]:
        #     sb_config["route"]["final"] = "Auto-Select-All"

    with open(output_path, 'w') as f:
        json.dump(sb_config, f, indent=2, ensure_ascii=False)
    
    print(f"[+] Successfully merged {len(existing_proxy_tags)} (SB) + {len(new_clash_tags)} (Clash) proxies.")
    print(f"[+] Combined group 'Auto-Select-All' created.")
    print(f"[+] Saved to: {output_path}")

if __name__ == "__main__":
    main()
