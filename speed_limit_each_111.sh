#!/bin/bash

# 设置默认的限速大小（以 Mbit/s 为单位）
default_limit=6  # 默认为8Mbit/s

# 选择网络接口
interface="eth0"  # 请根据实际情况修改

# 函数：设置限速
set_limit() {
    # 清除现有的限速规则
    tc qdisc del dev "$interface" root 2>/dev/null

    # 设置根队列规则
    tc qdisc add dev "$interface" root handle 1: htb default 10
    tc class add dev "$interface" parent 1: classid 1:1 htb rate "${default_limit}Mbit"

    # 创建限速规则
    ip_addresses=("10.0.0.4" "10.0.0.5" "10.0.0.6" "10.0.0.7" "10.0.0.8" "10.0.0.11" "10.0.0.12" "10.0.0.13" "10.0.0.14" "10.0.0.15")

    # 初始化classid计数器
    class_id_counter=2

    for ip in "${ip_addresses[@]}"; do
        class_id="1:$class_id_counter"
        tc class add dev "$interface" parent 1:1 classid $class_id htb rate "${default_limit}Mbit"
        tc filter add dev "$interface" protocol ip parent 1:0 prio 1 u32 match ip src $ip flowid $class_id
        ((class_id_counter++))  # 递增class_id计数器
    done

    # 输出绿色文本和实际限速速率
    echo -e "\e[32m限速规则已设置，实际限速速率为 ${default_limit} Mbit/s。\e[0m"
}

# 函数：删除限速
remove_limit() {
    # 清除现有的限速规则
    tc qdisc del dev "$interface" root 2>/dev/null

    # 输出绿色文本，表示规则已删除
    echo -e "\e[32m限速规则已删除。\e[0m"
}

# 主程序
if [ "$1" == "set" ]; then
    set_limit
elif [ "$1" == "remove" ]; then
    remove_limit
else
    echo "用法: $0 {set|remove}"
    exit 1
fi
