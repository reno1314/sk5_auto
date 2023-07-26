#!/bin/bash

# 使用ip命令获取网络接口名称
IFACE=$(ip -o -4 route show to default | awk '{print $5}')

# 将网络速度限制设置为10 Mbps
LIMIT_SPEED=10mbit

# Traffic Control规则的标记
TC_RULE_MARK=12

# Traffic Control规则所在的文件
TC_RULE_FILE="/etc/network/if-pre-up.d/tc_limit_speed"

# Traffic Control恢复规则所在的文件
TC_RESTORE_FILE="/etc/network/if-post-down.d/tc_restore"

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
    sudo tc qdisc del dev $IFACE root

    # 定义IP地址范围
    start_ip=4
    end_ip=15

    # 删除每个IP地址的限速规则
    for ((ip=$start_ip; ip<=$end_ip; ip++)); do
        TARGET_IP="10.0.0.$ip"
        sudo iptables -D OUTPUT -t mangle -s $TARGET_IP -j MARK --set-mark $TC_RULE_MARK
        sudo iptables -D INPUT -t mangle -d $TARGET_IP -j MARK --set-mark $TC_RULE_MARK
    done
}

# 添加Traffic Control恢复规则到定时任务
add_tc_restore_to_cron() {
    CRON_FILE="/etc/cron.d/tc_restore_speed"
    CRON_ENTRY="@reboot root /bin/bash $TC_RESTORE_FILE"
    echo "$CRON_ENTRY" | sudo tee $CRON_FILE
}

# 删除Traffic Control恢复规则从定时任务
remove_tc_restore_from_cron() {
    CRON_FILE="/etc/cron.d/tc_restore_speed"
    sudo rm -f $CRON_FILE
}

# 创建Traffic Control恢复规则脚本
create_tc_restore_script() {
    sudo tee $TC_RESTORE_FILE > /dev/null <<EOL
#!/bin/bash

# 恢复Traffic Control规则
/bin/bash $0 1
EOL
    sudo chmod +x $TC_RESTORE_FILE
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
            add_tc_restore_to_cron
            echo "网络速度已限制为10 Mbps，IP地址范围从10.0.0.4到10.0.0.15的所有设备受影响。"
            ;;
        2)
            remove_tc_rule
            remove_tc_restore_from_cron
            echo "限制的网络速度已移除，IP地址范围从10.0.0.4到10.0.0.15的所有设备不再受影响。"
            ;;
        *)
            echo "无效的选项，请输入1或2。"
            ;;
    esac
fi
