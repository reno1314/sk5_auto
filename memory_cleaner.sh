#!/bin/bash

# 设置内存使用率的阈值，超过此值将清理缓存
THRESHOLD=80

# ANSI颜色代码
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 安装命令
install() {
  # 将脚本复制到/usr/local/bin，并赋予执行权限
  cp $0 /usr/local/bin/memory_cleaner.sh
  chmod +x /usr/local/bin/memory_cleaner.sh

  # 创建systemd服务文件以实现开机自启
  cat <<EOF >/etc/systemd/system/memory_cleaner.service
[Unit]
Description=Memory Cleaner Service

[Service]
Type=simple
ExecStart=/usr/local/bin/memory_cleaner.sh run

[Install]
WantedBy=multi-user.target
EOF

  # 重新加载systemd管理器配置，启用并立即启动服务
  systemctl daemon-reload
  systemctl enable memory_cleaner.service
  systemctl start memory_cleaner.service

  echo -e "${GREEN}内存清理服务已安装成功并启动。${NC}"
}

# 卸载命令
uninstall() {
  # 停止服务并禁用开机自启
  systemctl stop memory_cleaner.service
  systemctl disable memory_cleaner.service

  # 删除systemd服务文件并重新加载配置
  rm -f /etc/systemd/system/memory_cleaner.service
  systemctl daemon-reload

  # 从/usr/local/bin删除脚本
  rm -f /usr/local/bin/memory_cleaner.sh

  echo -e "${GREEN}内存清理脚本已被完全卸载。${NC}"
}

# 清理内存的函数
clean_memory() {
  echo -e "${GREEN}内存清理服务开始运行...${NC}"
  while true; do
    # 获取总内存和可用内存
    total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

    # 计算当前内存使用率
    used=$(( (total - available) * 100 / total ))

    # 如果内存使用率超过阈值，则清理缓存
    if [ "$used" -gt "$THRESHOLD" ]; then
      echo "内存使用率超过${THRESHOLD}%，正在清理缓存..."
      echo 3 > /proc/sys/vm/drop_caches
    fi

    # 每隔15分检查一次
    sleep 900
  done
}

# 根据传入的参数执行对应的命令
case "$1" in
  install)
    install
    ;;
  uninstall)
    uninstall
    ;;
  run)
    clean_memory
    ;;
  *)
    echo "用法: $0 {install|uninstall|run}"
    ;;
esac
