#!/bin/bash

read -p "请输入要使用的端口号 (例如 59808): " PORT
if [ -z "$PORT" ]; then
    echo "❌ 端口号不能为空！"
    exit 1
fi

WEBROOT="/var/www/html"

echo "✅ 更新系统并安装所需软件..."
apt update && apt install -y apache2 php php-cli php-xml unzip curl firewalld ufw iptables iptables-persistent

echo "✅ 修改 Apache 监听端口..."
if ! grep -q "Listen ${PORT}" /etc/apache2/ports.conf; then
    echo "Listen ${PORT}" >> /etc/apache2/ports.conf
fi

echo "✅ 下载并安装 h5ai..."
cd ${WEBROOT}
wget -O h5ai.zip https://release.larsjung.de/h5ai/h5ai-0.30.0.zip
unzip -o h5ai.zip && rm h5ai.zip

echo "✅ 设置权限..."
chown -R www-data:www-data ${WEBROOT}/_h5ai

echo "✅ 配置 Apache 虚拟主机..."
cat <<EOF > /etc/apache2/sites-available/h5ai.conf
<VirtualHost *:${PORT}>
    DocumentRoot ${WEBROOT}
    <Directory "${WEBROOT}">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

a2enmod rewrite
a2ensite h5ai.conf
a2dissite 000-default.conf

echo "✅ 备份默认 index.html..."
if [ -f "${WEBROOT}/index.html" ]; then
    mv "${WEBROOT}/index.html" "${WEBROOT}/index.html.bak"
    echo "已备份为 index.html.bak"
else
    echo "未找到 index.html，无需备份"
fi

echo "✅ 检查并部署 index.php..."
if [ -f "${WEBROOT}/index.php" ]; then
    echo "index.php 已存在"
else
    if [ -f "${WEBROOT}/_h5ai/public/index.php" ]; then
        cp "${WEBROOT}/_h5ai/public/index.php" "${WEBROOT}/index.php"
        echo "已复制 _h5ai/public/index.php 到根目录"
    else
        echo "⚠ 错误：_h5ai/public/index.php 不存在，请检查 h5ai 安装！"
        exit 1
    fi
fi

echo "✅ 重启 Apache 服务..."
systemctl restart apache2

echo "✅ 检测防火墙并放行端口 ${PORT}..."

# ufw 放行
if command -v ufw >/dev/null 2>&1; then
    ufw status | grep -qw "active"
    if [ $? -eq 0 ]; then
        echo "检测到 ufw，放行端口 ${PORT}..."
        ufw allow ${PORT}/tcp
        ufw reload
        echo "ufw 放行端口完成。"
    fi
fi

# firewalld 放行
if command -v firewall-cmd >/dev/null 2>&1; then
    systemctl is-active firewalld >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "检测到 firewalld，放行端口 ${PORT}..."
        firewall-cmd --permanent --add-port=${PORT}/tcp
        firewall-cmd --reload
        echo "firewalld 放行端口完成。"
    fi
fi

# iptables 持久化放行
if command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT -p tcp --dport ${PORT} -j ACCEPT >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "检测到 iptables，添加放行端口规则 ${PORT}..."
        iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
        echo "保存 iptables 规则确保重启后生效..."
        netfilter-persistent save
        echo "iptables 规则已添加并持久化。"
    else
        echo "iptables 已存在放行端口 ${PORT} 的规则。"
    fi
fi

public_ip=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)
echo "✅ 安装配置完成！请访问: http://${public_ip}:${PORT}/"
