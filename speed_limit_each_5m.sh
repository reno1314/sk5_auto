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
    # 删除旧的 iptables 规则
    iptables -D OUTPUT -m set --match-set limitedips src -j MARK --set-mark 1 || true
    iptables -D INPUT -m set --match-set limitedips dst -j MARK --set-mark 1 || true

    # 删除旧的 ipset
    ipset destroy limitedips || true
    ipset create limitedips hash:ip

    for i in {4..20}; do
        ipset add limitedips "10.0.0.$i" || true
    done

    # 添加新的 iptables 规则
    iptables -A OUTPUT -m set --match-set limitedips src -j MARK --set-mark 1
    iptables -A INPUT -m set --match-set limitedips dst -j MARK --set-mark 1
    iptables -A POSTROUTING -t mangle -j CONNMARK --save-mark

    # Configure traffic control
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
    
    ipset destroy limitedips || true
    tc qdisc del dev "$selected_interface" root || true
    tc qdisc del dev "$selected_interface" ingress || true
    echo "已删除所有限速规则"
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
