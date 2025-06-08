#!/bin/bash

# 端口交互（范围限制）
while true; do
    read -p "请输入要使用的端口号（30999~60999）: " PORT
    if [[ $PORT =~ ^[0-9]+$ ]] && [ "$PORT" -ge 30999 ] && [ "$PORT" -le 60999 ]; then
        if ss -tln | grep -q ":$PORT"; then
            echo "端口 $PORT 已被占用，请更换其他端口。"
        else
            break
        fi
    else
        echo "请输入有效的端口号（30999~60999）"
    fi
done

# 系统识别
if [ -e /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "无法识别操作系统，终止安装。"
    exit 1
fi

echo "[INFO] 检测到系统: $OS $VER"

# 安装函数
install_packages() {
    case "$OS" in
        ubuntu|debian)
            apt update
            apt install -y apache2 php php-cli php-xml unzip wget
            WEB_DIR="/var/www/html"
            APACHE_CONF_DIR="/etc/apache2/sites-available"
            APACHE_PORTS_CONF="/etc/apache2/ports.conf"
            SYSTEMCTL="systemctl"
            ;;
        centos|rocky|almalinux)
            if [ "$VER" -ge 8 ]; then
                dnf install -y httpd php php-cli php-xml unzip wget
            else
                yum install -y epel-release
                yum install -y httpd php php-cli php-xml unzip wget
            fi
            WEB_DIR="/var/www/html"
            APACHE_CONF_DIR="/etc/httpd/conf.d"
            APACHE_PORTS_CONF="/etc/httpd/conf/httpd.conf"
            SYSTEMCTL="systemctl"
            ;;
        *)
            echo "[ERROR] 暂不支持的系统: $OS"
            exit 1
            ;;
    esac
}

# 添加 Apache 监听端口
add_apache_port() {
    if ! grep -q "Listen $PORT" "$APACHE_PORTS_CONF"; then
        echo "Listen $PORT" >> "$APACHE_PORTS_CONF"
    fi
}

# 创建虚拟主机配置
create_vhost_conf() {
    VHOST_CONF="$APACHE_CONF_DIR/h5ai.conf"
    cat <<EOF > "$VHOST_CONF"
<VirtualHost *:$PORT>
    DocumentRoot "$WEB_DIR"
    <Directory "$WEB_DIR">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog logs/h5ai_error.log
    CustomLog logs/h5ai_access.log combined
</VirtualHost>
EOF
}

# 下载和部署 h5ai
setup_h5ai() {
    cd "$WEB_DIR" || exit
    wget -O h5ai.zip https://release.larsjung.de/h5ai/h5ai-0.30.0.zip
    unzip -q h5ai.zip && rm -f h5ai.zip
    chown -R $(whoami):$(whoami) "$WEB_DIR/_h5ai"
    chown -R www-data:www-data "$WEB_DIR/_h5ai" 2>/dev/null || chown -R apache:apache "$WEB_DIR/_h5ai" 2>/dev/null
}

# 启动服务并输出结果
enable_and_show() {
    case "$OS" in
        ubuntu|debian)
            a2enmod rewrite
            a2ensite h5ai.conf
            ;;
    esac
    $SYSTEMCTL restart apache2 2>/dev/null || $SYSTEMCTL restart httpd
    IP=$(hostname -I | awk '{print $1}')
    echo
    echo "✅ 安装完成，请访问： http://$IP:$PORT/"
    echo
}

# 开始安装流程
install_packages
add_apache_port
create_vhost_conf
setup_h5ai
enable_and_show
