#!/bin/bash

# 获取当前脚本的路径和名称
script_path="$(readlink -f "$0")"
script_name="$(basename "$script_path")"

# 设置默认的限速大小（以 Mbit/s 为单位）
default_limit=16  # 默认为15Mbit/s

# Function to check and install TC on CentOS
install_tc_centos() {
  if ! command -v tc &>/dev/null; then
    echo "未找到TC，正在自动安装..."
    yum install -y iproute
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

# Function to check and install TC on Debian/Ubuntu
install_tc_debian_ubuntu() {
  if ! command -v tc &>/dev/null; then
    echo "未找到TC，正在自动安装..."
    apt-get update
    apt-get install -y iproute2
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
  # Use ip command to get a list of network interfaces that are up and not "lo" (loopback)
  network_interfaces=$(ip -o link show | awk -F': ' '!/lo/ && /state UP/{print $2}')
  
  if [ -z "$network_interfaces" ]; then
    echo "未找到适用的网络接口，无法进行Traffic Control配置。"
    exit 1
  fi
  
  # Automatically select the first suitable network interface
  selected_interface=$(echo "$network_interfaces" | awk 'NR==1{print $1}')
  echo "已选择网络接口：$selected_interface"
}

# Determine the Linux distribution
if [ -e /etc/os-release ]; then
  source /etc/os-release  # 导入分发版信息
  case "$ID" in
    "centos"|"rhel")
      if [ "$VERSION_ID" == "7" ]; then
        install_tc_centos
      else
        echo "不支持的CentOS版本。"
        exit 1
      fi
      ;;
    "debian"|"ubuntu")
      install_tc_debian_ubuntu
      ;;
    *)
      echo "未知的Linux分发版，无法自动安装TC。"
      exit 1
      ;;
  esac
else
  echo "未知的Linux分发版，无法自动安装TC。"
  exit 1
fi

# Detect a suitable network interface
detect_network_interface

# 设置总带宽为默认值
setup_traffic_control() {
  tc qdisc add dev "$selected_interface" root handle 1: htb default 10
  tc class add dev "$selected_interface" parent 1: classid 1:1 htb rate "${default_limit}Mbit"
}

# 创建限速规则
create_traffic_control() {
  ip_addresses=("10.0.0.4" "10.0.0.5" "10.0.0.6" "10.0.0.7" "10.0.0.8" "10.0.0.11" "10.0.0.12" "10.0.0.13" "10.0.0.14" "10.0.0.15")

  # 初始化classid计数器
  class_id_counter=2

  # 为每个IP地址创建分类和过滤器
  for ip in "${ip_addresses[@]}"
  do
    # 使用不同的classid格式：1:2 + 递增的整数
    class_id="1:$((class_id_counter++))"
    tc class add dev "$selected_interface" parent 1:1 classid $class_id htb rate "${default_limit}Mbit"
    tc filter add dev "$selected_interface" parent 1:0 protocol ip prio 1 u32 match ip src $ip flowid $class_id
    echo "已为IP地址 $ip 创建独立限速规则"
  done

  echo "已完成配置，每个不同的IP地址独立限速${default_limit}Mbit带宽。"
}

# 删除限速规则
delete_traffic_control() {
  # 删除根分类和所有子分类
  tc qdisc del dev "$selected_interface" root

  # 删除分类和过滤器
  for i in {2..11}; do
    tc class del dev "$selected_interface" classid 1:$i
    tc filter del dev "$selected_interface" parent 1: protocol ip prio 1 u32
  done

  # 停止并禁用 systemd 服务
  systemctl stop "$script_name"
  systemctl disable "$script_name"

  # 删除 systemd 服务文件
  rm "/etc/systemd/system/$script_name.service"

  # 重新加载 systemd 管理的服务
  systemctl daemon-reload

  # 删除 systemd 服务文件
  rm -f /root/speed_limit_each.sh
  
  echo "已删除所有的限速规则及服务。"
}

# 检查脚本参数
if [ "$1" != "create" ] && [ "$1" != "delete" ]; then
  echo "Usage: $0 [create | delete]"
  exit 1
fi

if [ "$1" == "create" ]; then
  setup_traffic_control
  create_traffic_control
elif [ "$1" == "delete" ]; then
  delete_traffic_control
fi

# 获取脚本的路径和名称
script_path="$(readlink -f "$0")"
script_name="$(basename "$script_path")"

# 获取 your_traffic_control_script.sh 的路径
your_tc_script="$script_path"

# 将服务设置为在启动时自动运行
if [ "$1" == "create" ]; then
  # 创建一个 systemd 服务单元
  cat <<EOF > "/etc/systemd/system/$script_name.service"
[Unit]
Description=Traffic Control Script
After=network.target

[Service]
ExecStart=$your_tc_script create
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  # 启用并运行服务
  systemctl daemon-reload
  systemctl enable "$script_name"
  systemctl start "$script_name"
fi
