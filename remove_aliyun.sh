#!/bin/bash

# 停止所有阿里云相关进程
sudo pkill -9 -f AliYun
sudo pkill -9 -f aliyun-service
sudo pkill -9 -f AliYunDun
sudo pkill -9 -f AliYunDun+

# 查找并杀死所有阿里云相关进程
for pid in $(ps aux | grep -E 'aliyun|AliYunDun|aegis' | grep -v grep | awk '{print $2}'); do
    sudo kill -9 $pid
done

# 停止和禁用阿里云相关服务
for service in aegis aliyun-service cloudmonitor assist-daemon; do
    sudo systemctl stop $service 2>/dev/null
    sudo systemctl disable $service 2>/dev/null
done

# 删除阿里云相关目录
sudo rm -rf /usr/local/aegis
sudo rm -rf /usr/local/cloudmonitor
sudo rm -rf /usr/local/share/assist-daemon
sudo rm -rf /etc/systemd/system/aliyun*
sudo rm -rf /etc/systemd/system/aegis*
sudo rm -rf /var/lib/aliyun-service
sudo rm -rf /var/lib/cloudmonitor

# 防止阿里云自动恢复
echo -e '#!/bin/bash\nexit 0' | sudo tee /usr/local/share/assist-daemon/assist_daemon.sh
sudo chmod +x /usr/local/share/assist-daemon/assist_daemon.sh

# 执行阿里云官方卸载脚本
sudo curl -sSL http://update.aegis.aliyun.com/download/uninstall.sh | sudo bash
sudo curl -sSL http://update.aegis.aliyun.com/download/quartz_uninstall.sh | sudo bash

# 重新加载 systemd
sudo systemctl daemon-reload

# 删除所有残留文件
sudo find / -name "*aliyun*" -exec rm -rf {} \; 2>/dev/null
sudo find / -name "*aegis*" -exec rm -rf {} \; 2>/dev/null

# 提示完成
echo "阿里云监控与阿里云盾已彻底删除！建议重启服务器。"

# 询问是否重启
read -p "是否立即重启服务器？(y/n): " choice
if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
    sudo reboot
fi
