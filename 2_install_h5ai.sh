#!/bin/bash

# 提示用户输入端口
read -p "请输入要使用的端口号 (例如 59808): " PORT

# 检查输入是否为空
if [ -z "$PORT" ]; then
    echo "端口号不能为空！"
    exit 1
fi

# 更新系统并安装所需软件
apt update && apt install -y apache2 php php-cli php-xml unzip curl

# 修改 Apache 监听端口
if ! grep -q "Listen ${PORT}" /etc/apache2/ports.conf; then
    echo "Listen ${PORT}" >> /etc/apache2/ports.conf
fi

# 进入 Web 目录
cd /var/www/html

# 下载 h5ai
wget -O h5ai.zip https://release.larsjung.de/h5ai/h5ai-0.30.0.zip

# 解压 h5ai
unzip h5ai.zip && rm h5ai.zip

# 赋予适当权限
chown -R www-data:www-data /var/www/html/_h5ai

# 配置 Apache 虚拟主机
cat <<EOF > /etc/apache2/sites-available/h5ai.conf
<VirtualHost *:${PORT}>
    DocumentRoot /var/www/html
    <Directory "/var/www/html">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

# 启用模块和站点
a2enmod rewrite
a2ensite h5ai.conf

# 关闭默认 80 端口站点（可选）
a2dissite 000-default.conf

# 重启 Apache 使配置生效
systemctl restart apache2

# 获取公网 IP
public_ip=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)

echo "h5ai 安装完成！"
echo "请访问: http://${public_ip}:${PORT}/"
