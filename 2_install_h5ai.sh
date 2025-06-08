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
            APACHE_LOG_DIR="/var/log/apache2"
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
            APACHE_LOG_DIR="/var/log/httpd"
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
    DocumentRoot $WEB_DIR
    <Directory "$WEB_DIR">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    Alias /_h5ai /var/www/h5ai_core/_h5ai
    <Directory "/var/www/h5ai_core/_h5ai">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog ${APACHE_LOG_DIR}/h5ai_error.log
    CustomLog ${APACHE_LOG_DIR}/h5ai_access.log combined
</VirtualHost>
EOF
}

# 下载和部署 h5ai
setup_h5ai() {
    H5AI_CORE="/var/www/h5ai_core"
    mkdir -p "$H5AI_CORE"
    cd "$H5AI_CORE"

    if ! wget -O h5ai.zip https://github.com/lrsjng/h5ai/releases/download/v0.30.0/h5ai-0.30.0.zip; then
        echo "❌ h5ai 下载失败，请手动下载 h5ai.zip 到 $H5AI_CORE 并解压。"
        exit 1
    fi

    unzip -q h5ai.zip && rm -f h5ai.zip
    chown -R www-data:www-data "$H5AI_CORE/_h5ai" 2>/dev/null || chown -R apache:apache "$H5AI_CORE/_h5ai" 2>/dev/null
}

# 启用 Apache 配置
enable_apache_conf() {
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        a2enmod rewrite
        a2ensite h5ai.conf
    fi
}

# 启动服务并输出信息
enable_and_show() {
    if command -v apache2 > /dev/null; then
        APACHE_SERVICE="apache2"
        CONFIG_FILE="/etc/apache2/apache2.conf"
    else
        APACHE_SERVICE="httpd"
        CONFIG_FILE="/etc/httpd/conf/httpd.conf"
    fi

    # 添加 ServerName
    if ! grep -q "^ServerName" "$CONFIG_FILE"; then
        echo "🌐 添加 ServerName localhost 到 $CONFIG_FILE"
        echo "ServerName localhost" >> "$CONFIG_FILE"
    fi

    echo "🔍 检查配置语法..."
    apachectl configtest

    echo "🚀 重启 Apache 服务..."
    systemctl restart "$APACHE_SERVICE"

    echo "📈 Apache 当前状态："
    systemctl status "$APACHE_SERVICE" --no-pager

    echo "🔎 当前监听端口："
    ss -tulnp | grep "$APACHE_SERVICE" || ss -tulnp | grep ":$PORT"

    IP=$(hostname -I | awk '{print $1}')
    echo
    echo "✅ 安装完成，请访问： http://$IP:$PORT/"
    echo
}

# 清理默认文件
clean_up() {
    rm -f /var/www/html/index.html
    rm -rf /var/www/html/_h5ai
}

# 执行流程
install_packages
add_apache_port
create_vhost_conf
setup_h5ai
enable_apache_conf
enable_and_show
clean_up
