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

function install_v2ray()
{
    echo "begin to install v2ray"
    ssh -T -o StrictHostKeyChecking=no root@${vps_ip} 2>&1 << eof
    bash <(curl -L https://raw.githubusercontent.com/JayYang1991/fhs-install-v2ray/master/install-release.sh)
    exit
eof
    echo "install v2ray $vps_ip success"
}

if [ ! -z "$vps_ip" ];then
    echo "vps $vps_ip is exist"
    install_v2ray
    exit 0
fi
echo "begin to create instance"
vultr-cli instance create --region=$my_region --plan=$my_plan --os=$my_os --host=$my_host --label=$my_lable --tags=$my_tag --ssh-keys=$my_ssh_keys --ipv6
if [ $? -ne 0 ];then
    echo "create instance failed."
    exit 1;
fi
sleep 30
vps_ip=$(vultr-cli instance list | grep $my_lable | awk '{print $2}')
if [ -z "$vps_ip" ];then
    echo "vps $vps_ip is not exist"
    exit 1
fi

install_v2ray


