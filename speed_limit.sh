#!/bin/bash

# 使用ip命令获取网络接口名称
IFACE=$(ip -o -4 route show to default | awk '{print $5}')

# Traffic Control规则的标记
TC_RULE_MARK=12

# Traffic Control恢复规则所在的文件
TC_RESTORE_FILE="/etc/rc.local"

# Traffic Control限速规则
LIMIT_SPEED=15mbit

# 添加Traffic Control限速规则
add_tc_rule() {
    # 创建Traffic Control类并设置限速规则
    tc qdisc add dev $IFACE root handle 1: htb default 12
    tc class add dev $IFACE parent 1: classid 1:12 htb rate $LIMIT_SPEED

    # 定义IP地址范围
    start_ip=4
    end_ip=15

    # 配置每个IP地址的限速规则
    for ((ip=$start_ip; ip<=$end_ip; ip++)); do
        TARGET_IP="10.0.0.$ip"

        # 使用iptables过滤指定IP的流量并将其定向到限速类
        iptables -A OUTPUT -t mangle -s $TARGET_IP -j MARK --set-mark $TC_RULE_MARK
        iptables -A INPUT -t mangle -d $TARGET_IP -j MARK --set-mark $TC_RULE_MARK
    done
}

# 删除Traffic Control限速规则
remove_tc_rule() {
    # 删除Traffic Control类和iptables规则
    tc qdisc del dev $IFACE root &>/dev/null

    # 定义IP地址范围
    start_ip=4
    end_ip=15

    # 删除每个IP地址的限速规则
    for ((ip=$start_ip; ip<=$end_ip; ip++)); do
        TARGET_IP="10.0.0.$ip"
        iptables -D OUTPUT -t mangle -s $TARGET_IP -j MARK --set-mark $TC_RULE_MARK 2>/dev/null
        iptables -D INPUT -t mangle -d $TARGET_IP -j MARK --set-mark $TC_RULE_MARK 2>/dev/null
    done
}

# 创建Traffic Control恢复规则脚本
create_tc_restore_script() {
    # 删除旧的恢复规则
    sed -i '/tc qdisc add dev/d' $TC_RESTORE_FILE

    # 创建Traffic Control恢复规则
    cat <<EOL | sudo tee -a $TC_RESTORE_FILE > /dev/null
tc qdisc add dev $IFACE root handle 1: htb default 12
tc class add dev $IFACE parent 1: classid 1:12 htb rate $LIMIT_SPEED

start_ip=4
end_ip=15

for ((ip=\$start_ip; ip<=\$end_ip; ip++)); do
    TARGET_IP="10.0.0.\$ip"
    iptables -A OUTPUT -t mangle -s \$TARGET_IP -j MARK --set-mark $TC_RULE_MARK
    iptables -A INPUT -t mangle -d \$TARGET_IP -j MARK --set-mark $TC_RULE_MARK
done
EOL

    # 修改脚本权限
    sudo chmod +x $TC_RESTORE_FILE
}

if [ $# -eq 0 ]; then
    echo "请输入选项："
    echo "  $0 1 : 批量增加限速"
    echo "  $0 2 : 批量删除限制"
else
    case $1 in
        1)
            add_tc_rule
            create_tc_restore_script
            echo "网络速度已限制为15 Mbps，IP地址范围从10.0.0.4到10.0.0.15的所有设备受影响。"
            ;;
        2)
            remove_tc_rule
            echo "限制的网络速度已移除，IP地址范围从10.0.0.4到10.0.0.15的所有设备不再受影响。"
            ;;
        *)
            echo "无效的选项，请输入1或2。"
            ;;
    esac
fi
