#!/bin/bash

# 使用ip命令获取网络接口名称
IFACE=$(ip -o -4 route show to default | awk '{print $5}')

# 将网络速度限制设置为15 Mbps
LIMIT_SPEED=15mbit

# Traffic Control规则的标记
TC_RULE_MARK=12

# 检查是否已经安装了版本正确的TC
check_tc_installed() {
    if tc -h &>/dev/null; then
        echo "TC已安装，继续执行脚本。"
    else
        echo "未找到TC或版本不正确，开始安装TC..."
        install_tc
    fi
}

# 安装TC
install_tc() {
    # 在CentOS/RHEL系统上安装TC
    if [ -f /etc/redhat-release ]; then
        sudo yum install -y iproute2
    # 在Ubuntu/Debian系统上安装TC
    elif [ -f /etc/lsb-release ]; then
        sudo apt-get update
        sudo apt-get install -y iproute2
    else
        echo "未知的Linux发行版，无法自动安装TC。请手动安装TC并重试。"
        exit 1
    fi

    if tc -h &>/dev/null; then
        echo "TC安装成功，继续执行脚本。"
    else
        echo "TC安装失败，请手动安装TC并重试。"
        exit 1
    fi
}

# 添加Traffic Control规则
add_tc_rule() {
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
        sudo iptables -A OUTPUT -t mangle -s $TARGET_IP -j MARK --set-mark $TC_RULE_MARK
        sudo iptables -A INPUT -t mangle -d $TARGET_IP -j MARK --set-mark $TC_RULE_MARK
    done
}

# 删除Traffic Control规则
remove_tc_rule() {
    # 删除Traffic Control类和iptables规则
    sudo tc qdisc del dev $IFACE root &>/dev/null

    # 定义IP地址范围
    start_ip=4
    end_ip=15

    # 删除每个IP地址的限速规则
    for ((ip=$start_ip; ip<=$end_ip; ip++)); do
        TARGET_IP="10.0.0.$ip"
        sudo iptables -D OUTPUT -t mangle -s $TARGET_IP -j MARK --set-mark $TC_RULE_MARK 2>/dev/null
        sudo iptables -D INPUT -t mangle -d $TARGET_IP -j MARK --set-mark $TC_RULE_MARK 2>/dev/null
    done
}

# 创建Traffic Control恢复规则脚本
create_tc_restore_script() {
    RESTORE_SCRIPT="/etc/network/tc_restore_speed.sh"
    sudo tee $RESTORE_SCRIPT > /dev/null <<EOL
#!/bin/bash

# 恢复Traffic Control规则
$(declare -f add_tc_rule)
add_tc_rule
EOL
    sudo chmod +x $RESTORE_SCRIPT
}

# 添加恢复规则脚本到/etc/rc.local中
add_tc_restore_to_rc_local() {
    if ! grep -q "$RESTORE_SCRIPT" /etc/rc.local; then
        sudo sed -i -e "\$i $RESTORE_SCRIPT\n" /etc/rc.local
    fi
}

check_tc_installed

if [ $# -eq 0 ]; then
    echo "请输入选项："
    echo "  $0 1 : 批量增加限速"
    echo "  $0 2 : 批量删除限制"
else
    case $1 in
        1)
            add_tc_rule
            create_tc_restore_script
            add_tc_restore_to_rc_local
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
