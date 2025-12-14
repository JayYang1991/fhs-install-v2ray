#!/bin/bash
my_lable="ubuntu_2204"
vps_ip=$(vultr-cli instance list | grep $my_lable | awk '{print $2}')
while [ -z "$vps_ip" -o "$vps_ip" == "0.0.0.0" ];do	
    echo "vps $vps_ip is not exist"
    sleep 1
    vps_ip=$(vultr-cli instance list | grep $my_lable | awk '{print $2}')
    vps_ip="0.0.0.1"
done
