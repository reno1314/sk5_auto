#!/bin/bash

# 获取当前脚本的路径和名称
script_path="$(readlink -f "$0")"
script_name="$(basename "$script_path")"

# 设置默认的限速大小（以 Mbit/s 为单位）
default_limit=8  # 默认为15Mbit/s

# Function to install TC on supported distros
install_tc() {
  if ! command -v tc &>/dev/null; then
    echo "未找到TC，正在自动安装..."
    if [[ -f /etc/debian_version ]]; then
      apt-get update && apt-get install -y iproute2
    elif [[ -f /etc/redhat-release ]]; then
      yum install -y iproute
    else
      echo "不支持的Linux分发版，无法自动安装TC。"
      exit 1
    fi

    if [ $? -eq 0 ]; then
      echo "TC已成功安装。"
    else
      echo "TC安装失败，请手动安装后重新运行此脚本。"
      exit 1
    fi
  else
    echo "TC已安装。"
  fi
}

# Function to detect a suitable network interface
detect_network_interface() {
  selected_interface=$(ip -o link show | awk -F': ' '!/lo/ && /state UP/{print $2}' | head -n 1)
  if [ -z "$selected_interface" ]; then
    echo "未找到适用的网络接口，无法进行Traffic Control配置。"
    exit 1
  fi
  echo "已选择网络接口：$selected_interface"
}

# 设置总带宽为默认值
setup_traffic_control() {
  tc qdisc add dev "$selected_interface" root handle 1: htb default 10
  tc class add dev "$selected_interface" parent 1: classid 1:1 htb rate "${default_limit}Mbit"
}

# 创建限速规则
create_traffic_control() {
  ip_addresses=("10.0.0.4" "10.0.0.5" "10.0.0.6" "10.0.0.7" "10.0.0.8" "10.0.0.11" "10.0.0.12" "10.0.0.13" "10.0.0.14" "10.0.0.15")
  class_id_counter=2

  for ip in "${ip_addresses[@]}"; do
    class_id="1:$((class_id_counter++))"
    tc class add dev "$selected_interface" parent 1:1 classid $class_id htb rate "${default_limit}Mbit"
    tc filter add dev "$selected_interface" parent 1:0 protocol ip prio 1 u32 match ip src $ip flowid $class_id
  done
  echo "已完成配置，每个不同的IP地址独立限速${default_limit}Mbit带宽。"
}

# 删除限速规则
delete_traffic_control() {
  tc qdisc del dev "$selected_interface" root
  systemctl stop "$script_name"
  systemctl disable "$script_name"
  rm "/etc/systemd/system/$script_name.service"
  systemctl daemon-reload
  rm -f /root/speed_limit_each.sh
  echo "已删除所有的限速规则及服务。"
}

# 检查脚本参数
if [ "$1" != "create" ] && [ "$1" != "delete" ]; then
  echo "Usage: $0 [create | delete]"
  exit 1
fi

install_tc
detect_network_interface

if [ "$1" == "create" ]; then
  setup_traffic_control
  create_traffic_control
elif [ "$1" == "delete" ]; then
  delete_traffic_control
fi

# 设置服务在启动时自动运行
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
