#!/bin/bash
set -e
set -u

# 设置默认的限速大小（以 Mbit/s 为单位）
default_limit=5  # 默认为5Mbit/s
interface="eth0" # 修改为你的网络接口名称

# Function to create ipset list and iptables rules
create_limits() {
    ipset create limitedips hash:ip || true

    for i in {4..20}; do
        ipset add limitedips "10.0.0.$i" || true
    done
    
    iptables -A OUTPUT -m set --match-set limitedips src -j MARK --set-mark 1 || true
    iptables -A INPUT -m set --match-set limitedips dst -j MARK --set-mark 1 || true
    iptables -A POSTROUTING -t mangle -j CONNMARK --save-mark || true

    tc qdisc add dev "$interface" root handle 1: htb default 30 || true
    tc class add dev "$interface" parent 1: classid 1:1 htb rate 1000mbit || true
    tc class add dev "$interface" parent 1:1 classid 1:10 htb rate "${default_limit}mbit" || true
    tc filter add dev "$interface" protocol ip parent 1:0 prio 1 handle 1 fw flowid 1:10 || true

    tc qdisc add dev "$interface" handle ffff: ingress || true
    tc filter add dev "$interface" protocol ip parent ffff: prio 1 handle 1 fw flowid 1:10 || true

    echo "已为每个 IP 地址独立限速 ${default_limit} Mbit/s（下载和上传）"
}

# Function to delete ipset list and iptables rules
delete_limits() {
    iptables -D OUTPUT -m set --match-set limitedips src -j MARK --set-mark 1 || true
    iptables -D INPUT -m set --match-set limitedips dst -j MARK --set-mark 1 || true
    ipset destroy limitedips || true
    
    tc qdisc del dev "$interface" root || true
    tc qdisc del dev "$interface" ingress || true

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

# 创建 systemd 服务
script_path="$(readlink -f "$0")"
script_name="$(basename "$script_path")"

if [ "$1" == "create" ]; then
    cat <<EOF > "/etc/systemd/system/$script_name.service"
[Unit]
Description=Traffic Control Script
After=network.target

[Service]
ExecStart=$script_path create
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$script_name"
    systemctl start "$script_name"
fi

# 卸载命令
if [ "$1" == "delete" ]; then
    delete_limits
    systemctl stop "$script_name" || true
    systemctl disable "$script_name" || true
    rm "/etc/systemd/system/$script_name.service" || true
    systemctl daemon-reload
fi
