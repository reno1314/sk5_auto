#!/bin/bash

set -e

read -p "请输入要使用的端口号 (例如 12345): " PORT
if [ -z "$PORT" ]; then
    echo "❌ 端口号不能为空！"
    exit 1
fi

WEBROOT="/var/www/html"

# 系统检测函数
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        echo "无法识别操作系统！"
        exit 1
    fi
}

install_packages_ubuntu_debian() {
    apt update
    apt install -y apache2 php php-cli php-xml unzip curl ufw iptables iptables-persistent
}

install_packages_centos7() {
    yum install -y epel-release
    yum install -y httpd php php-cli php-xml unzip curl firewalld iptables-services
}

install_packages_centos8() {
    dnf install -y epel-release
    dnf install -y httpd php php-cli php-xml unzip curl firewalld iptables-services
}

setup_firewall_ubuntu_debian() {
    # ufw 启用并放行端口
    if command -v ufw >/dev/null 2>&1; then
        ufw status | grep -qw "active" || ufw enable
        ufw allow ${PORT}/tcp
        ufw reload
        echo "ufw 放行端口 ${PORT}"
    fi
}

setup_firewall_centos() {
    # firewalld 启用并放行端口
    if systemctl is-active firewalld >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=${PORT}/tcp
        firewall-cmd --reload
        echo "firewalld 放行端口 ${PORT}"
    else
        # firewalld 未启动，尝试启动
        systemctl start firewalld
        firewall-cmd --permanent --add-port=${PORT}/tcp
        firewall-cmd --reload
        echo "firewalld 启动并放行端口 ${PORT}"
    fi
}

setup_iptables_persistent() {
    if command -v iptables >/dev/null 2>&1; then
        iptables -C INPUT -p tcp --dport ${PORT} -j ACCEPT >/dev/null 2>&1 || {
            iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
            echo "添加 iptables 端口放行 ${PORT}"
        }

        if command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save
        elif command -v service >/dev/null 2>&1 && service iptables save >/dev/null 2>&1; then
            service iptables save
        else
            echo "⚠️ 无法自动保存 iptables 规则，请手动保存"
        fi
    fi
}

configure_apache_listen() {
    local port=$1
    local apache_ports_conf=""
    case "$OS" in
        ubuntu|debian)
            apache_ports_conf="/etc/apache2/ports.conf"
            ;;
        centos)
            apache_ports_conf="/etc/httpd/conf/httpd.conf"
            ;;
        *)
            echo "未知系统，默认使用 /etc/apache2/ports.conf"
            apache_ports_conf="/etc/apache2/ports.conf"
            ;;
    esac

    if ! grep -q "Listen ${port}" "$apache_ports_conf"; then
        echo "Listen ${port}" >> "$apache_ports_conf"
        echo "已添加 Listen ${port} 到 $apache_ports_conf"
    else
        echo "$apache_ports_conf 中已存在 Listen ${port}"
    fi
}

configure_apache_vhost() {
    local port=$1
    local apache_conf=""
    case "$OS" in
        ubuntu|debian)
            apache_conf="/etc/apache2/sites-available/h5ai.conf"
            ;;
        centos)
            apache_conf="/etc/httpd/conf.d/h5ai.conf"
            ;;
        *)
            apache_conf="/etc/apache2/sites-available/h5ai.conf"
            ;;
    esac

    cat <<EOF > "${apache_conf}"
<VirtualHost *:${port}>
    DocumentRoot ${WEBROOT}
    <Directory "${WEBROOT}">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

    echo "已生成 Apache 虚拟主机配置文件: ${apache_conf}"
}

enable_apache_site_and_modules() {
    case "$OS" in
        ubuntu|debian)
            a2enmod rewrite
            a2ensite h5ai.conf
            a2dissite 000-default.conf
            ;;
        centos)
            # centos默认启用，确认无默认站点冲突即可
            ;;
    esac
}

restart_apache() {
    case "$OS" in
        ubuntu|debian)
            systemctl restart apache2
            ;;
        centos)
            systemctl restart httpd
            ;;
        *)
            systemctl restart apache2
            ;;
    esac
}

backup_and_prepare_webroot() {
    # 备份 index.html
    if [ -f "${WEBROOT}/index.html" ]; then
        mv "${WEBROOT}/index.html" "${WEBROOT}/index.html.bak"
        echo "已备份 index.html 为 index.html.bak"
    fi

    # 复制 index.php
    if [ ! -f "${WEBROOT}/index.php" ]; then
        if [ -f "${WEBROOT}/_h5ai/public/index.php" ]; then
            cp "${WEBROOT}/_h5ai/public/index.php" "${WEBROOT}/index.php"
            echo "已复制 _h5ai/public/index.php 到根目录"
        else
            echo "⚠️ 未找到 _h5ai/public/index.php，请检查 h5ai 安装"
            exit 1
        fi
    else
        echo "index.php 已存在，跳过复制"
    fi
}

main() {
    detect_os
    echo "检测到系统: $OS $VER"

    # 安装依赖
    case "$OS" in
        ubuntu|debian)
            install_packages_ubuntu_debian
            ;;
        centos)
            if [[ "$VER" == 7* ]]; then
                install_packages_centos7
            else
                install_packages_centos8
            fi
            ;;
        *)
            echo "当前系统未明确支持，尝试用 Debian/Ubuntu 方式安装..."
            install_packages_ubuntu_debian
            ;;
    esac

    # 配置 apache 监听端口
    configure_apache_listen $PORT

    # 下载并安装 h5ai
    mkdir -p $WEBROOT
    cd $WEBROOT
    wget -O h5ai.zip https://release.larsjung.de/h5ai/h5ai-0.30.0.zip
    unzip -o h5ai.zip && rm h5ai.zip
    chown -R www-data:www-data ${WEBROOT}/_h5ai

    # 配置 apache 虚拟主机
    configure_apache_vhost $PORT

    # 启用模块和站点
    enable_apache_site_and_modules

    # 备份并准备网站根目录
    backup_and_prepare_webroot

    # 重启 apache
    restart_apache

    # 防火墙放行端口
    case "$OS" in
        ubuntu|debian)
            setup_firewall_ubuntu_debian
            ;;
        centos)
            setup_firewall_centos
            ;;
        *)
            echo "未知系统，尝试通用防火墙配置"
            setup_firewall_ubuntu_debian
            ;;
    esac

    # iptables 持久化放行端口
    setup_iptables_persistent

    public_ip=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)
    echo "✅ 安装完成，请访问：http://${public_ip}:${PORT}/"
}

main
