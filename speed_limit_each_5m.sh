#!/bin/bash
set -e
set -u

# 设置默认的限速大小（以 Mbit/s 为单位）
default_limit=5  # 默认为5Mbit/s

# Function to create ipset list and iptables rules
create_limits() {
    ipset create limitedips hash:ip

    for i in {4..20}; do
        ipset add limitedips "10.0.0.$i"
    done
    
    iptables -A OUTPUT -m set --match-set limitedips src -j MARK --set-mark 1
    iptables -A INPUT -m set --match-set limitedips dst -j MARK --set-mark 1
    iptables -A POSTROUTING -t mangle -j CONNMARK --save-mark

    tc qdisc add dev eth0 root handle 1: htb default 30
    tc class add dev eth0 parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev eth0 parent 1:1 classid 1:10 htb rate "${default_limit}mbit"
    tc filter add dev eth0 protocol ip parent 1:0 prio 1 handle 1 fw flowid 1:10

    tc qdisc add dev eth0 handle ffff: ingress
    tc filter add dev eth0 protocol ip parent ffff: prio 1 handle 1 fw flowid 1:10

    echo "已为每个 IP 地址独立限速 ${default_limit} Mbit/s（下载和上传）"
}

# Function to delete ipset list and iptables rules
delete_limits() {
    iptables -D OUTPUT -m set --match-set limitedips src -j MARK --set-mark 1 || true
    iptables -D INPUT -m set --match-set limitedips dst -j MARK --set-mark 1 || true
    ipset destroy limitedips || true
    
    tc qdisc del dev eth0 root || true
    tc qdisc del dev eth0 ingress || true

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
