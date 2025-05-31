#!/bin/bash
set -euo pipefail

# 脚本必须以 root 用户运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请以 root 用户运行此脚本"
    exit 1
fi

read -rp "请输入要使用的端口号 (例如 12345): " PORT
if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then
    echo "❌ 端口号必须为数字！"
    exit 1
fi

WEBROOT="/var/www/html"

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        OS_LIKE=$ID_LIKE
    else
        echo "无法识别操作系统！"
        exit 1
    fi
}

install_packages_debian_like() {
    echo "更新包列表..."
    apt update -qq
    echo "安装必要包..."
    DEBIAN_FRONTEND=noninteractive apt install -y apache2 php php-cli php-xml unzip curl ufw iptables iptables-persistent wget
}

install_packages_rhel_like() {
    echo "安装必要包..."
    if command -v dnf &>/dev/null; then
        dnf install -y epel-release || true
        dnf install -y httpd php php-cli php-xml unzip curl firewalld iptables-services wget
    else
        yum install -y epel-release || true
        yum install -y httpd php php-cli php-xml unzip curl firewalld iptables-services wget
    fi
}

install_packages_arch() {
    echo "安装必要包..."
    pacman -Syu --noconfirm apache php php-apache unzip curl iptables wget
}

install_packages_opensuse() {
    echo "安装必要包..."
    zypper refresh
    zypper install -y apache2 php7 php7-xml unzip curl SuSEfirewall2 iptables wget
}

install_dependencies() {
    case "$OS" in
        ubuntu|debian)
            install_packages_debian_like
            ;;
        centos|rhel|fedora)
            install_packages_rhel_like
            ;;
        arch)
            install_packages_arch
            ;;
        opensuse*|suse)
            install_packages_opensuse
            ;;
        *)
            if [[ "$OS_LIKE" == *"debian"* ]]; then
                install_packages_debian_like
            elif [[ "$OS_LIKE" == *"rhel"* ]] || [[ "$OS_LIKE" == *"fedora"* ]]; then
                install_packages_rhel_like
            else
                echo "未知系统，尝试使用 Debian/Ubuntu 方式安装依赖"
                install_packages_debian_like
            fi
            ;;
    esac
}

get_apache_ports_conf() {
    case "$OS" in
        ubuntu|debian) echo "/etc/apache2/ports.conf" ;;
        centos|rhel|fedora|arch) echo "/etc/httpd/conf/httpd.conf" ;;
        opensuse*|suse) echo "/etc/apache2/listen.conf" ;;
        *) echo "/etc/apache2/ports.conf" ;;
    esac
}

get_apache_vhost_conf() {
    case "$OS" in
        ubuntu|debian) echo "/etc/apache2/sites-available/h5ai.conf" ;;
        centos|rhel|fedora|arch) echo "/etc/httpd/conf.d/h5ai.conf" ;;
        opensuse*|suse) echo "/etc/apache2/vhosts.d/h5ai.conf" ;;
        *) echo "/etc/apache2/sites-available/h5ai.conf" ;;
    esac
}

configure_apache_listen() {
    local port=$1
    local conf_file
    conf_file=$(get_apache_ports_conf)

    if grep -qE "^\s*Listen\s+${port}$" "$conf_file"; then
        echo "$conf_file 中已存在 Listen ${port}"
    else
        echo "Listen ${port}" >> "$conf_file"
        echo "已添加 Listen ${port} 到 $conf_file"
    fi
}

configure_apache_vhost() {
    local port=$1
    local conf_file
    conf_file=$(get_apache_vhost_conf)

    if [ -f "${conf_file}" ]; then
        cp "${conf_file}" "${conf_file}.bak.$(date +%F-%T)"
    fi

    cat <<EOF > "${conf_file}"
<VirtualHost *:${port}>
    DocumentRoot ${WEBROOT}
    <Directory "${WEBROOT}">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

    echo "已生成 Apache 虚拟主机配置文件: ${conf_file}"
}

enable_apache_site_and_modules() {
    case "$OS" in
        ubuntu|debian)
            a2enmod rewrite
            a2ensite h5ai.conf
            a2dissite 000-default.conf || true
            ;;
        centos|rhel|fedora|arch)
            # 通常 rewrite 模块已启用，无需额外操作
            ;;
        opensuse*|suse)
            a2enmod rewrite || true
            ;;
    esac
}

restart_apache() {
    case "$OS" in
        ubuntu|debian) systemctl restart apache2 ;;
        centos|rhel|fedora|arch) systemctl restart httpd ;;
        opensuse*|suse) systemctl restart apache2 ;;
        *) systemctl restart apache2 ;;
    esac
}

setup_firewall() {
    local port=$1

    if command -v ufw &>/dev/null; then
        if ! ufw status | grep -qw "active"; then
            echo y | ufw enable
        fi
        ufw allow "${port}/tcp"
        ufw reload
        echo "ufw 放行端口 ${port}"
    elif systemctl is-active firewalld &>/dev/null; then
        if ! firewall-cmd --list-ports | grep -qw "${port}/tcp"; then
            firewall-cmd --permanent --add-port=${port}/tcp
            firewall-cmd --reload
        fi
        echo "firewalld 放行端口 ${port}"
    elif command -v iptables &>/dev/null; then
        if ! iptables -C INPUT -p tcp --dport "${port}" -j ACCEPT &>/dev/null; then
            iptables -I INPUT -p tcp --dport "${port}" -j ACCEPT
            echo "添加 iptables 端口放行 ${port}"
        fi

        # 尝试保存规则，兼容多种系统
        if command -v netfilter-persistent &>/dev/null; then
            netfilter-persistent save
        elif command -v service &>/dev/null && service iptables save &>/dev/null; then
            service iptables save
        elif command -v iptables-save &>/dev/null; then
            iptables-save > /etc/iptables/rules.v4 || echo "⚠️ 无法保存 iptables 规则到 /etc/iptables/rules.v4"
        else
            echo "⚠️ 无法自动保存 iptables 规则，请手动保存"
        fi
    else
        echo "⚠️ 无防火墙管理工具，无法自动放行端口，请手动处理"
    fi
}

backup_and_prepare_webroot() {
    if [ -f "${WEBROOT}/index.html" ]; then
        mv -v "${WEBROOT}/index.html" "${WEBROOT}/index.html.bak"
    fi

    if [ ! -f "${WEBROOT}/index.php" ]; then
        if [ -f "${WEBROOT}/_h5ai/public/index.php" ]; then
            cp -v "${WEBROOT}/_h5ai/public/index.php" "${WEBROOT}/index.php"
        else
            echo "⚠️ 未找到 _h5ai/public/index.php，请检查 h5ai 安装"
            exit 1
        fi
    else
        echo "index.php 已存在，跳过复制"
    fi
}

install_curl_if_missing() {
    if command -v curl &>/dev/null; then
        return 0
    fi
    echo "curl 未安装，尝试自动安装 curl..."

    case "$OS" in
        ubuntu|debian)
            apt update -qq
            DEBIAN_FRONTEND=noninteractive apt install -y curl
            ;;
        centos|rhel|fedora)
            if command -v dnf &>/dev/null; then
                dnf install -y curl
            else
                yum install -y curl
            fi
            ;;
        arch)
            pacman -Sy --noconfirm curl
            ;;
        opensuse*|suse)
            zypper install -y curl
            ;;
        *)
            echo "未知系统，无法自动安装 curl，请手动安装"
            return 1
            ;;
    esac

    if command -v curl &>/dev/null; then
        echo "curl 安装成功"
        return 0
    else
        echo "curl 安装失败，请手动安装"
        return 1
    fi
}

download_h5ai() {
    local url="https://github.com/lrsjng/h5ai/releases/download/v0.30.0/h5ai-0.30.0.zip"
    local output="h5ai.zip"

    if command -v curl &>/dev/null; then
        echo "使用 curl 下载 h5ai..."
        if ! curl -fsSL --retry 3 -o "$output" "$url"; then
            echo "⚠️ curl 下载失败，尝试用 wget 下载..."
            if command -v wget &>/dev/null; then
                if ! wget -q --tries=3 --timeout=15 -O "$output" "$url"; then
                    echo "❌ h5ai 下载失败！"
                    return 1
                fi
            else
                echo "❌ wget 未安装，无法下载 h5ai！"
                return 1
            fi
        fi
    else
        echo "curl 未安装，尝试安装..."
        if install_curl_if_missing; then
            download_h5ai  # 重新调用自己，安装完curl后再下载
        else
            echo "尝试用 wget 下载..."
            if command -v wget &>/dev/null; then
                if ! wget -q --tries=3 --timeout=15 -O "$output" "$url"; then
                    echo "❌ h5ai 下载失败！"
                    return 1
                fi
            else
                echo "❌ wget 未安装，无法下载 h5ai！"
                return 1
            fi
        fi
    fi
    echo "h5ai 下载成功"
    return 0
}

main() {
    detect_os
    echo "检测到系统: $OS $VER"

    install_dependencies

    configure_apache_listen "$PORT"

    mkdir -p "$WEBROOT"
    cd "$WEBROOT" || { echo "无法进入目录 $WEBROOT"; exit 1; }

    echo "正在下载 h5ai ..."
    if ! download_h5ai; then
        exit 1
    fi

    unzip -o h5ai.zip && rm -f h5ai.zip

    if [ ! -d "${WEBROOT}/_h5ai" ]; then
        echo "⚠️ 解压后未找到 _h5ai 目录，请检查下载包结构"
        exit 1
    fi

    # 支持更多用户，如 www-data apache http nginx 等
    for user in www-data apache http nginx; do
        if id "$user" &>/dev/null; then
            chown -R "$user":"$user" "${WEBROOT}/_h5ai"
            break
        fi
    done

    configure_apache_vhost "$PORT"

    enable_apache_site_and_modules

    backup_and_prepare_webroot

    restart_apache

    setup_firewall "$PORT"

    public_ip=$(curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 ipinfo.io/ip || echo "无法获取公网 IP")
    echo "✅ 安装完成，请访问：http://${public_ip}:${PORT}/"
}

main
