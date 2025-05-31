#!/bin/bash

# 提示用户输入端口
read -p "请输入要使用的端口号 (例如 59808): " PORT

# 检查输入是否为空
if [ -z "$PORT" ]; then
    echo "端口号不能为空！"
    exit 1
fi

# 更新系统并安装所需软件
if [ -f /etc/redhat-release ]; then
    # CentOS
    yum install -y epel-release
    yum install -y httpd php php-cli php-xml unzip curl firewalld
    systemctl enable httpd
    systemctl start httpd
else
    # Debian / Ubuntu
    apt update && apt install -y apache2 php php-cli php-xml unzip curl ufw
    systemctl enable apache2
    systemctl start apache2
fi

# 修改 Apache/Httpd 监听端口
if [ -f /etc/httpd/conf/httpd.conf ]; then
    # CentOS (httpd)
    if ! grep -q "Listen ${PORT}" /etc/httpd/conf/httpd.conf; then
        echo "Listen ${PORT}" >> /etc/httpd/conf/httpd.conf
    fi
else
    # Debian/Ubuntu (apache2)
    if ! grep -q "Listen ${PORT}" /etc/apache2/ports.conf; then
        echo "Listen ${PORT}" >> /etc/apache2/ports.conf
    fi
fi

# 进入 Web 目录
cd /var/www/html || cd /var/www

# 下载 h5ai
wget -O h5ai.zip https://release.larsjung.de/h5ai/h5ai-0.30.0.zip

# 解压 h5ai
unzip h5ai.zip && rm h5ai.zip

# 赋予适当权限
chown -R www-data:www-data ./_h5ai 2>/dev/null || chown -R apache:apache ./_h5ai

# 配置 Apache/Httpd 虚拟主机
if [ -f /etc/httpd/conf.d/h5ai.conf ]; then
    # CentOS
    cat <<EOF > /etc/httpd/conf.d/h5ai.conf
<VirtualHost *:${PORT}>
    DocumentRoot "/var/www/html"
    <Directory "/var/www/html">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
else
    # Debian/Ubuntu
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
    a2enmod rewrite
    a2ensite h5ai.conf
    a2dissite 000-default.conf
fi

# 重启服务
if [ -f /etc/httpd/conf/httpd.conf ]; then
    systemctl restart httpd
else
    systemctl restart apache2
fi

# 放行端口检测
echo "检测并放行防火墙端口..."

# UFW 检测
if command -v ufw >/dev/null 2>&1; then
    ufw_status=$(ufw status | head -n 1)
    if [[ "$ufw_status" == "Status: active" ]]; then
        echo "UFW 检测到已启用，正在放行端口 ${PORT}..."
        ufw allow ${PORT}/tcp
    else
        echo "UFW 未启用，无需修改。"
    fi
fi

# Firewalld 检测 (CentOS 7/8)
if systemctl is-active firewalld >/dev/null 2>&1; then
    echo "Firewalld 检测到已启用，正在放行端口 ${PORT}..."
    firewall-cmd --permanent --add-port=${PORT}/tcp
    firewall-cmd --reload
else
    echo "Firewalld 未启用。"
fi

# Iptables 检测（备用）
if command -v iptables >/dev/null 2>&1; then
    if iptables -L INPUT -n | grep -q "${PORT}"; then
        echo "Iptables 中已存在端口 ${PORT} 规则。"
    else
        echo "正在用 Iptables 放行端口 ${PORT}..."
        iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
        service iptables save 2>/dev/null || iptables-save > /etc/iptables.rules
    fi
fi

# 获取公网 IP
public_ip=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)

echo ""
echo "✅ h5ai 安装完成！"
echo "🌐 请访问: http://${public_ip}:${PORT}/"
echo "⚠ 注意：请确保在云服务提供商（如甲骨文云、阿里云、AWS、GCP）控制台的安全组中放行端口 ${PORT}，否则外网无法访问！"
