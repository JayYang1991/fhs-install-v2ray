#!/bin/bash
# create
my_region="nrt"
my_plan="vc2-1c-1gb"
my_os="1743"
my_host="jayyang"
my_lable="ubuntu_2204"
my_tag="v2ray"
my_ssh_keys="c5e8bf26-ab13-454a-a827-c2afff006a67,fa784b8e-c8d9-40d3-ab66-c7b0177a4013"
vps_ip=$(vultr-cli instance list | grep $my_lable | awk '{print $2}')
script_id="89005eb6-6e67-40fb-b873-c8399295f05e"

function install_v2ray()
{
    echo "begin to install v2ray"
    ssh -T -o StrictHostKeyChecking=no root@${vps_ip} 2>&1 << eof
    bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-v2ray-proxy-server.sh)
    exit
eof
    echo "install v2ray $vps_ip success"
}


function check_ssh_until_success() {
    local host="$1"
    local port="${2:-22}"
    local timeout="${3:-4}"
    local max_attempts="${4:-60}"
    local interval="${5:-5}"
    
    local attempt=1
    local success=false
    
    while [[ $attempt -le $max_attempts && "$success" == false ]]; do
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=$timeout -l root -p "$port" "$host" "echo 'SSH连接成功'" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            success=true
            return 0
        fi
        
        # 等待间隔时间再尝试
        if [[ $attempt -lt $max_attempts ]]; then
            sleep $interval
        fi
        
        ((attempt++))
    done
    
    return 1
}

function update_local_v2ray_agent_config() {
    local bash_config_file=$(ls ~/.bashrc)
    local v2ray_config_file="/usr/local/etc/v2ray/config.json"
    local origin_v2ray_config_file="/tmp/proxy_client_config.json"
    local download_config_link="https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/proxy_client_config.json"
    echo "Downloading V2Ray config: $download_config_link"
    if ! curl -R -H 'Cache-Control: no-cache' -o "$origin_v2ray_config_file" "$download_config_link"; then
        echo 'error: Download failed! Please check your network or try again.'
        return 1
    fi
    sed -i s/V2RAY_PROXY_SERVER_IP=.*/V2RAY_PROXY_SERVER_IP=$vps_ip/g $bash_config_file
    sed -i s/\{V2RAY_PROXY_SERVER_IP\}/$vps_ip/g $origin_v2ray_config_file
    sed -i s/\{V2RAY_PROXY_ID\}/${V2RAY_PROXY_ID}/g $origin_v2ray_config_file
    sed -i s/\{V2RAY_REVERSE_SERVER_IP\}/${V2RAY_REVERSE_SERVER_IP}/g $origin_v2ray_config_file
    sed -i s/\{V2RAY_REVERSE_ID\}/${V2RAY_REVERSE_ID}/g $origin_v2ray_config_file
    sudo \cp $origin_v2ray_config_file $v2ray_config_file
    sudo systemctl restart v2ray.service 
    if [ $? -ne 0 ];then
        echo 'restart v2ray failed.'
        return 1
    fi
    echo "update local v2ray agent config success."
    return 0
}

if [ ! -z "$vps_ip" ];then
    echo "vps $vps_ip is exist"
    install_v2ray
    update_local_v2ray_agent_config
    exit 0
fi
echo "begin to create instance"
vultr-cli instance create --region=$my_region --plan=$my_plan --os=$my_os --script-id=$script_id --host=$my_host --label=$my_lable --tags=$my_tag --ssh-keys=$my_ssh_keys --ipv6
if [ $? -ne 0 ];then
    echo "create instance failed."
    exit 1;
fi

vps_ip=$(vultr-cli instance list | grep $my_lable | awk '{print $2}')
while [ -z "$vps_ip" -o "$vps_ip" == "0.0.0.0" ];do
    echo "vps $vps_ip is not exist"
    sleep 2
    vps_ip=$(vultr-cli instance list | grep $my_lable | awk '{print $2}')
done

check_ssh_until_success $vps_ip

install_v2ray

update_local_v2ray_agent_config



