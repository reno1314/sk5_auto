#!/bin/bash

# 设置默认的限速大小（以 Mbit/s 为单位）
default_limit=5  # 默认为5Mbit/s

# Function to create ipset list and iptables rules
create_limits() {
    # IP 地址范围从 10.0.0.4 到 10.0.0.20
    ip_addresses=()
    for i in {4..20}; do
        ip_addresses+=("10.0.0.$i")
    done
    
    # 创建 ipset 列表
    ipset create limitedips hash:ip
    
    # 添加 IP 地址到 ipset 列表
    for ip in "${ip_addresses[@]}"; do
        ipset add limitedips $ip
    done
    
    # 设置 iptables 规则，将 ipset 列表中的 IP 流量进行标记
    iptables -A OUTPUT -m set --match-set limitedips src -j MARK --set-mark 1
    iptables -A POSTROUTING -t mangle -j CONNMARK --save-mark

    # 使用 tc 对标记的流量进行限速
    tc qdisc add dev eth0 root handle 1: htb default 30
    tc class add dev eth0 parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev eth0 parent 1:1 classid 1:10 htb rate ${default_limit}mbit
    tc filter add dev eth0 protocol ip parent 1:0 prio 1 handle 1 fw flowid 1:10

    echo "已为每个 IP 地址独立限速 ${default_limit} Mbit/s"
}

# Function to delete ipset list and iptables rules
delete_limits() {
    # 删除 iptables 规则和 ipset 列表
    iptables -D OUTPUT -m set --match-set limitedips src -j MARK --set-mark 1
    iptables -D POSTROUTING -t mangle -j CONNMARK --save-mark
    ipset destroy limitedips
    
    # 删除 tc 规则
    tc qdisc del dev eth0 root
    
    echo "已删除所有限速规则"
}

# 检查脚本参数
if [ "$1" != "create" ] && [ "$1" != "delete" ]; then
    echo "Usage: $0 [create | delete]"
    exit 1
fi

if [ "$1" == "create" ]; then
    create_limits
elif [ "$1" == "delete" ]; then
    delete_limits
fi

# 获取脚本的路径和名称
script_path="$(readlink -f "$0")"
script_name="$(basename "$script_path")"

# 获取 your_traffic_control_script.sh 的路径
your_tc_script="$script_path"

# 将服务设置为在启动时自动运行
if [ "$1" == "create" ]; then
    # 创建一个 systemd 服务单元
    cat <<EOF > "/etc/systemd/system/$script_name.service"
[Unit]
Description=Traffic Control Script
After=network.target

[Service]
ExecStart=$your_tc_script create
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # 启用并运行服务
    systemctl daemon-reload
    systemctl enable "$script_name"
    systemctl start "$script_name"
fi
