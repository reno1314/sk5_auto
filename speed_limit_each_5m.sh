#!/bin/bash

# 获取网络接口
INTERFACE="eth0"
LIMIT=5Mbit

# 清理现有的 TC 配置
tc qdisc del dev "$INTERFACE" root 2>/dev/null

# 设置主队列规则
tc qdisc add dev "$INTERFACE" root handle 1: htb default 10

# 添加主类
tc class add dev "$INTERFACE" parent 1: classid 1:1 htb rate $LIMIT

# 创建 IP 限速规则
IP_ADDRESSES=("10.0.0.4" "10.0.0.5" "10.0.0.6" "10.0.0.7" "10.0.0.8" "10.0.0.11" "10.0.0.12" "10.0.0.13" "10.0.0.14" "10.0.0.15")

for IP in "${IP_ADDRESSES[@]}"; do
    # 下载限速
    tc class add dev "$INTERFACE" parent 1:1 classid 1:2 htb rate $LIMIT
    tc filter add dev "$INTERFACE" protocol ip parent 1:0 prio 1 u32 match ip src "$IP" flowid 1:2
    echo "已为IP地址 $IP 创建下载限速规则"

    # 上传限速
    tc class add dev "$INTERFACE" parent 1:1 classid 2:2 htb rate $LIMIT
    tc filter add dev "$INTERFACE" protocol ip parent 2:0 prio 1 u32 match ip dst "$IP" flowid 2:2
    echo "已为IP地址 $IP 创建上传限速规则"
done

echo "已完成配置，每个IP地址独立限速 $LIMIT 带宽。"

# 创建 systemd 服务
cat <<EOF > "/etc/systemd/system/speed_limit_each.sh.service"
[Unit]
Description=Traffic Control Script
After=network.target

[Service]
ExecStart=$(realpath "$0") create
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动服务
systemctl daemon-reload
systemctl enable speed_limit_each.sh.service
systemctl start speed_limit_each.sh.service
