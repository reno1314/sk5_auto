#!/bin/bash

# 使用ip命令获取网络接口名称
IFACE=$(ip -o -4 route show to default | awk '{print $5}')

LIMIT_SPEED=20mbit

function add_limit {
    # 创建Traffic Control类并设置限速规则
    sudo tc qdisc add dev $IFACE root handle 1: htb default 12
    sudo tc class add dev $IFACE parent 1: classid 1:12 htb rate $LIMIT_SPEED

    # 定义IP地址范围
    start_ip=4
    end_ip=15

    # 配置每个IP地址的限速规则
    for ((ip=$start_ip; ip<=$end_ip; ip++)); do
        TARGET_IP="10.0.0.$ip"

        # 使用iptables过滤指定IP的流量并将其定向到限速类
        sudo iptables -A OUTPUT -t mangle -s $TARGET_IP -j MARK --set-mark 12
        sudo iptables -A INPUT -t mangle -d $TARGET_IP -j MARK --set-mark 12
    done

    # 保存iptables规则以便在重启后仍然有效
    sudo service iptables save

    echo "网络速度已限制为1 Mbps，IP地址范围从10.0.0.4到10.0.0.15的所有设备受影响。"
}

function remove_limit {
    # 删除Traffic Control类和iptables规则
    sudo tc qdisc del dev $IFACE root

    # 定义IP地址范围
    start_ip=4
    end_ip=15

    # 删除每个IP地址的限速规则
    for ((ip=$start_ip; ip<=$end_ip; ip++)); do
        TARGET_IP="10.0.0.$ip"
        sudo iptables -D OUTPUT -t mangle -s $TARGET_IP -j MARK --set-mark 12
        sudo iptables -D INPUT -t mangle -d $TARGET_IP -j MARK --set-mark 12
    done

    echo "限制的网络速度已移除，IP地址范围从10.0.0.4到10.0.0.15的所有设备不再受影响。"
}

if [ -z "$IFACE" ]; then
    echo "无法自动检测网络接口名称。请手动设置网络接口名称。"
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "请输入选项："
    echo "  1. 批量增加限速"
    echo "  2. 批量删除限制"
else
    case $1 in
        1)
            add_limit
            ;;
        2)
            remove_limit
            ;;
        *)
            echo "无效的选项，请输入1或2。"
            ;;
    esac
fi
