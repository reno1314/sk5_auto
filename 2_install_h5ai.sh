#!/bin/bash

# 提示输入端口，默认 8080
read -p "请输入要使用的端口（默认8080）: " PORT
PORT=${PORT:-8080}

# 检查输入是否合法（是否是数字）
if ! [[ $PORT =~ ^[0-9]+$ ]]; then
    echo "错误：端口必须是数字。"
    exit 1
fi

# 检查端口范围
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "错误：端口号必须在 1 到 65535 之间。"
    exit 1
fi

if [ "$PORT" -lt 1024 ]; then
    echo "⚠️ 警告：端口 $PORT 是系统保留端口，使用它需要 root 权限。"
fi

# 检查输入端口是否被占用
if ss -tuln | grep -q ":$PORT "; then
    echo "错误：端口 $PORT 已被占用，请更换其他端口后重试。"
    exit 1
fi

# 检查 80 和 443 是否被非 Apache 占用
for CHECK_PORT in 80 443; do
    PROC=$(ss -tulpn | grep ":$CHECK_PORT " | grep -v apache2 | awk '{print $NF}' | sed 's/.*pid=\([0-9]\+\),.*/\1/')
    if [ -n "$PROC" ]; then
        PROC_NAME=$(ps -p $PROC -o comm=)
        echo "⚠️ 注意：端口 $CHECK_PORT 被其他程序占用（PID $PROC，进程名 $PROC_NAME）。Apache 可能无法绑定到这些端口。"
    fi
done

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

# 启用 Apache 配置
a2enmod rewrite
a2ensite h5ai.conf
systemctl reload apache2

# 检查 Apache 服务状态
APACHE_STATUS=$(systemctl is-active apache2)
if [ "$APACHE_STATUS" != "active" ]; then
    echo "⚠️ 检测到 Apache 未运行，正在尝试启动..."
    systemctl start apache2
    if [ "$(systemctl is-active apache2)" == "active" ]; then
        echo "✅ Apache 已成功启动。"
    else
        echo "❌ 无法启动 Apache，请手动检查日志。"
        exit 1
    fi
fi

# 检查 ufw 状态并放行端口
if ufw status | grep -q "Status: active"; then
    ufw allow $PORT/tcp
    ufw reload
    echo "✅ 已自动放行防火墙端口 $PORT。"
fi

echo "🎉 h5ai 安装完成！请访问： http://你的服务器IP:$PORT/"
