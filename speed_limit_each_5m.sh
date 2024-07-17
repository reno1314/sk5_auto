#!/bin/bash

# 获取当前脚本的路径和名称
script_path="$(readlink -f "$0")"
script_name="$(basename "$script_path")"

# 设置默认的限速大小（以 Mbit/s 为单位）
default_limit=5Mbit

# 选择的网络接口
selected_interface="eth0"

# IP 地址数组
ip_addresses=("10.0.0.4" "10.0.0.5" "10.0.0.6" "10.0.0.7" "10.0.0.8" "10.0.0.11" "10.0.0.12" "10.0.0.13" "10.0.0.14" "10.0.0.15")

# 清理现有的 TC 配置
tc qdisc del dev "$selected_interface" root 2>/dev/null

# 设置主队列规则
tc qdisc add dev "$selected_interface" root handle 1: htb default 10
tc class add dev "$selected_interface" parent 1: classid 1:1 htb rate "$default_limit"

# 创建限速规则
for IP in "${ip_addresses[@]}"; do
    # 检查下载限速规则是否已存在
    if ! tc class show dev "$selected_interface" | grep -q "1:$((i + 2))"; then
        tc class add dev "$selected_interface" parent 1:1 classid 1:$((i + 2)) htb rate "$default_limit"
        tc filter add dev "$selected_interface" protocol ip parent 1:0 prio 1 u32 match ip src "$IP" flowid 1:$((i + 2))
        echo "已为IP地址 $IP 创建下载限速规则"
    else
        echo "下载限速规则已存在，跳过 $IP"
    fi

    # 检查上传限速规则是否已存在
    if ! tc class show dev "$selected_interface" | grep -q "2:$((i + 2))"; then
        tc class add dev "$selected_interface" parent 1:1 classid 2:$((i + 2)) htb rate "$default_limit"
        tc filter add dev "$selected_interface" protocol ip parent 2:0 prio 1 u32 match ip dst "$IP" flowid 2:$((i + 2))
        echo "已为IP地址 $IP 创建上传限速规则"
    else
        echo "上传限速规则已存在，跳过 $IP"
    fi
done

echo "已完成配置，每个IP地址独立限速 $default_limit 带宽。"

# 创建 systemd 服务
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

# 启用并启动服务
systemctl daemon-reload
systemctl enable "$script_name.service"
systemctl start "$script_name.service"
