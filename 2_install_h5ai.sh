#!/bin/bash

# ========= h5ai 自动安装脚本 =========

# 端口设置交互，范围30999~60999
while true; do
    read -p "请输入要使用的端口号（30999~60999）: " PORT
    if [[ $PORT =~ ^[0-9]+$ ]] && [ $PORT -ge 30999 ] && [ $PORT -le 60999 ]; then
        if lsof -i TCP:$PORT >/dev/null; then
            echo "端口 $PORT 已被占用，请选择其他端口。"
            continue
        fi
        break
    else
        echo "端口号无效，请输入30999~60999之间的数字。"
    fi
done

# 更新系统并安装所需软件
echo "[INFO] 正在更新系统并安装 Apache2 和 PHP..."
apt update && apt install -y apache2 php php-cli php-xml unzip

# 添加 Apache 监听端口（若未监听则添加）
if ! grep -q "Listen $PORT" /etc/apache2/ports.conf; then
    echo "Listen $PORT" >> /etc/apache2/ports.conf
fi

# 禁用默认站点（避免冲突）
a2dissite 000-default.conf

# 进入 Web 目录
cd /var/www/html || exit

# 下载 h5ai 最新版本
echo "[INFO] 正在下载 h5ai..."
wget -O h5ai.zip https://release.larsjung.de/h5ai/h5ai-0.30.0.zip

# 解压 h5ai 并清理压缩包
echo "[INFO] 正在解压 h5ai..."
unzip -q h5ai.zip && rm -f h5ai.zip

# 设置权限
echo "[INFO] 正在设置文件权限..."
chown -R www-data:www-data /var/www/html/_h5ai

# 创建 Apache 虚拟主机配置
echo "[INFO] 正在生成 Apache 配置..."
cat <<EOF > /etc/apache2/sites-available/h5ai.conf
<VirtualHost *:$PORT>
    DocumentRoot /var/www/html
    <Directory "/var/www/html">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# 启用模块和站点
echo "[INFO] 启用 Apache 模块与站点..."
a2enmod rewrite
a2ensite h5ai.conf

# 重启 Apache 服务
echo "[INFO] 正在重启 Apache 服务..."
systemctl restart apache2

# 获取本机 IP 地址
IP=$(hostname -I | awk '{print $1}')

# 显示结果
echo
echo "✅ h5ai 安装完成！"
echo "📂 请在浏览器中访问：http://$IP:$PORT/"
echo
