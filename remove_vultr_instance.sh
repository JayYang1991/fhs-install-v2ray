#!/bin/bash
# create
my_region="nrt"
my_plan="vc2-1c-1gb"
my_os="1743"
my_host="jayyang"
my_lable="ubuntu_2204"
my_tag="v2ray"
my_ssh_keys="48babc0d-43d4-4892-9f49-8d3bf324f71a,7ac473c1-142d-42e0-9711-4c48d4da7fee,fa784b8e-c8d9-40d3-ab66-c7b0177a4013"
vps_id=$(vultr-cli instance list | grep $my_lable | awk '{print $1}')
if [ -z "$vps_id" ];then
    echo "vps is not exist"
    exit 1
fi
echo "begin to remove instance"
vultr-cli instance delete $vps_id
if [ $? -ne 0 ];then
    echo "remove instance failed."
    exit 1;
fi
echo "remove vps $vps_ip success"
