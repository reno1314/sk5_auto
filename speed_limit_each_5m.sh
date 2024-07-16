#!/bin/bash
set -e
set -u

# 获取当前脚本的路径和名称
script_path="$(readlink -f "$0")"
script_name="$(basename "$script_path")"
default_limit=5  # 默认为5Mbit/s

# Function to check and install required tools
install_dependencies() {
  if ! command -v tc &>/dev/null || ! command -v ipset &>/dev/null; then
    echo "未找到tc或ipset，正在安装..."
    if [ -e /etc/os-release ]; then
      source /etc/os-release
      case "$ID" in
        "centos"|"rhel")
          yum install -y iproute ipset || { echo "安装失败"; exit 1; }
          ;;
        "debian"|"ubuntu")
          apt-get update && apt-get install -y iproute2 ipset || { echo "安装失败"; exit 1; }
          ;;
        *)
          echo "未知的Linux分发版，无法自动安装。"
          exit 1
          ;;
      esac
    else
      echo "未知的Linux分发版，无法自动安装。"
      exit 1
    fi
  fi
}

# Detect a suitable network interface
detect_network_interface() {
  network_interfaces=$(ip -o link show | awk -F': ' '!/lo/ && /state UP/{print $2}')
  
  if [ -z "$network_interfaces" ]; then
    echo "未找到适用的网络接口，无法进行Traffic Control配置。"
    exit 1
  fi
  
  selected_interface=$(echo "$network_interfaces" | awk 'NR==1{print $1}')
  echo "已选择网络接口：$selected_interface"
}

# Create limits with ipset and tc
create_limits() {
    # 创建 ipset 集合
    if ipset list limitedips &>/dev/null; then
        echo "ipset 集合 limitedips 已存在，正在删除..."
        ipset destroy limitedips || { echo "无法销毁现有的 ipset 集合"; exit 1; }
    fi

    ipset create limitedips hash:ip || { echo "ipset 集合创建失败"; exit 1; }

    for i in {4..20}; do
        ipset add limitedips "10.0.0.$i"
    done

    # 检查 ipset 集合是否正确创建
    if ! ipset list limitedips &>/dev/null; then
        echo "ipset 集合创建失败"; exit 1;
    fi
    echo "ipset 集合创建成功"

    # 添加 iptables 规则
    iptables -A OUTPUT -m set --match-set limitedips src -j MARK --set-mark 1
    iptables -A INPUT -m set --match-set limitedips dst -j MARK --set-mark 1
    iptables -A POSTROUTING -t mangle -j CONNMARK --save-mark

    # 检查 iptables 规则是否正确添加
    if ! iptables -C OUTPUT -m set --match-set limitedips src -j MARK --set-mark 1 &>/dev/null; then
        echo "iptables OUTPUT 规则添加失败"; exit 1;
    fi
    if ! iptables -C INPUT -m set --match-set limitedips dst -j MARK --set-mark 1 &>/dev/null; then
        echo "iptables INPUT 规则添加失败"; exit 1;
    fi
    echo "iptables 规则添加成功"

    # 配置流量控制
    tc qdisc del dev "$selected_interface" root || true
    tc qdisc del dev "$selected_interface" ingress || true

    # 设置总带宽
    tc qdisc add dev "$selected_interface" root handle 1: htb default 30
    tc class add dev "$selected_interface" parent 1: classid 1:1 htb rate 1000mbit
    tc class add dev "$selected_interface" parent 1:1 classid 1:10 htb rate "${default_limit}mbit"
    tc filter add dev "$selected_interface" protocol ip parent 1:0 prio 1 handle 1 fw flowid 1:10

    # 设置入站限速
    tc qdisc add dev "$selected_interface" handle ffff: ingress
    tc filter add dev "$selected_interface" protocol ip parent ffff: prio 1 handle 1 fw flowid 1:10

    echo "已为每个 IP 地址独立限速 ${default_limit} Mbit/s（下载和上传）"
}

# Delete limits
delete_limits() {
    # 删除旧的 iptables 规则
    iptables -D OUTPUT -m set --match-set limitedips src -j MARK --set-mark 1 || true
    iptables -D INPUT -m set --match-set limitedips dst -j MARK --set-mark 1 || true

    # 删除 tc 规则
    tc qdisc del dev "$selected_interface" root || true
    tc qdisc del dev "$selected_interface" ingress || true

    # 销毁 ipset
    ipset destroy limitedips || true
    
    # 删除 systemd 服务
    systemctl stop "$script_name" || true
    systemctl disable "$script_name" || true
    rm "/etc/systemd/system/$script_name.service" || true
    systemctl daemon-reload

    echo "已删除所有限速规则及 systemd 服务"
}

# 检查脚本参数
if [ "$1" != "create" ] && [ "$1" != "delete" ]; then
    echo "Usage: $0 [create | delete]"
    exit 1
fi

# 安装依赖项
install_dependencies
detect_network_interface

if [ "$1" == "create" ]; then
    create_limits
elif [ "$1" == "delete" ]; then
    delete_limits
fi

# 创建 systemd 服务
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
