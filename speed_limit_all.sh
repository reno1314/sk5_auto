#!/bin/bash

# 使用ip命令获取网络接口名称
IFACE=$(ip -o -4 route show to default | awk '{print $5}')

# 将网络速度限制设置为15 Mbps
LIMIT_SPEED=20mbit

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

# 检查是否已安装iptables-persistent
check_iptables_persistent_installed() {
    if [ -f /etc/lsb-release ]; then
        if dpkg -s iptables-persistent &>/dev/null; then
            echo "iptables-persistent已安装。"
        else
            echo "iptables-persistent未安装。开始安装iptables-persistent..."
            sudo apt-get update
            sudo apt-get install -y iptables-persistent
        fi
    fi
}

# 保存iptables规则
save_iptables_rules() {
    if [ -f /etc/lsb-release ]; then
        sudo iptables-save | sudo tee /etc/iptables/rules.v4
        sudo ip6tables-save | sudo tee /etc/iptables/rules.v6
    fi
}

# 添加Traffic Control规则到启动脚本
add_tc_to_startup() {
    # 创建Traffic Control规则
    tc_cmd="tc qdisc add dev $IFACE root handle 1: htb default 12"
    tc_cmd+=" && tc class add dev $IFACE parent 1: classid 1:12 htb rate $LIMIT_SPEED"

    # 判断是否支持systemd
    if pidof systemd &>/dev/null; then
        echo "使用systemd"
        # 创建一个自定义的systemd服务单元
        sudo tee /etc/systemd/system/tc_limit_speed.service > /dev/null <<EOF
[Unit]
Description=Limit Network Speed with Traffic Control
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "$tc_cmd"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        # 重新加载systemd服务
        sudo systemctl daemon-reload
        # 启用自定义的服务
        sudo systemctl enable tc_limit_speed.service
    else
        echo "使用rc.local"
        # 将Traffic Control规则写入rc.local脚本
        echo "#!/bin/bash" | sudo tee "/etc/rc.d/rc.local"
        echo $tc_cmd | sudo tee -a "/etc/rc.d/rc.local"
        echo "exit 0" | sudo tee -a "/etc/rc.d/rc.local"
        sudo chmod +x "/etc/rc.d/rc.local"
    fi
}

# 删除Traffic Control规则从启动脚本
remove_tc_from_startup() {
    # 判断是否支持systemd
    if pidof systemd &>/dev/null; then
        echo "使用systemd"
        # 禁用并删除自定义的服务
        sudo systemctl stop tc_limit_speed.service
        sudo systemctl disable tc_limit_speed.service
        sudo rm -f /etc/systemd/system/tc_limit_speed.service
        # 重新加载systemd服务
        sudo systemctl daemon-reload
    else
        echo "使用rc.local"
        # 从rc.local脚本中删除Traffic Control规则
        sudo sed -i '/tc qdisc add dev/d' /etc/rc.d/rc.local
        sudo sed -i '/tc class add dev/d' /etc/rc.d/rc.local
    fi
}

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
    save_iptables_rules
    # 添加Traffic Control规则到启动脚本
    add_tc_to_startup

    echo "网络速度已限制为20 Mbps，IP地址范围从10.0.0.4到10.0.0.15的所有设备受影响。"
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

    # 删除Traffic Control规则从启动脚本
    remove_tc_from_startup

    echo "限制的网络速度已移除，IP地址范围从10.0.0.4到10.0.0.15的所有设备不再受影响。"
}

check_tc_installed
check_iptables_persistent_installed

if [ $# -eq 0 ]; then
    echo "请输入选项："
    echo "  $0 1 : 批量增加限速"
    echo "  $0 2 : 批量删除限制"
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
