#!/bin/bash

# 你可以在这里自定义端口，例如 PORT=8080
PORT=11111

# 更新系统并安装所需软件
apt update && apt install -y apache2 php php-cli php-xml unzip

# 修改 Apache 监听端口
if ! grep -q "^Listen $PORT" /etc/apache2/ports.conf; then
    echo "Listen $PORT" >> /etc/apache2/ports.conf
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
<VirtualHost *:$PORT>
    DocumentRoot /var/www/html
    <Directory "/var/www/html">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

# 启用配置
a2enmod rewrite
a2ensite h5ai.conf
systemctl restart apache2

echo "h5ai 安装完成！请访问 http://你的服务器IP:$PORT/"
