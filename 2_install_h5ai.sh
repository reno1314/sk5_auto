#!/bin/bash
set -euo pipefail

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

is_installed() {
    command -v "$1" &>/dev/null
}

install_packages() {
    local pkgs=("$@")
    case "$OS" in
        ubuntu|debian)
            apt update -qq
            DEBIAN_FRONTEND=noninteractive apt install -y "${pkgs[@]}"
            ;;
        centos|rhel|fedora)
            if is_installed dnf; then
                dnf install -y "${pkgs[@]}"
            else
                yum install -y "${pkgs[@]}"
            fi
            ;;
        arch)
            pacman -Syu --noconfirm "${pkgs[@]}"
            ;;
        opensuse*|suse)
            zypper refresh
            zypper install -y "${pkgs[@]}"
            ;;
        *)
            echo "未知系统，尝试用 Debian/Ubuntu 方法"
            apt update -qq
            DEBIAN_FRONTEND=noninteractive apt install -y "${pkgs[@]}"
            ;;
    esac
}

install_dependencies() {
    local common_pkgs=(apache2 php php-cli php-xml unzip curl wget)
    detect_os
    echo "检测到系统: $OS $VER"

    # 根据系统定制额外包
    case "$OS" in
        ubuntu|debian)
            install_packages "${common_pkgs[@]}" ufw iptables iptables-persistent
            ;;
        centos|rhel|fedora)
            install_packages "${common_pkgs[@]}" firewalld iptables-services
            ;;
        arch)
            install_packages "${common_pkgs[@]}" iptables
            ;;
        opensuse*|suse)
            install_packages "${common_pkgs[@]}" SuSEfirewall2 iptables
            ;;
    esac
}

get_apache_service() {
    case "$OS" in
        ubuntu|debian|opensuse*|suse) echo "apache2" ;;
        centos|rhel|fedora|arch) echo "httpd" ;;
        *) echo "apache2" ;;
    esac
}

configure_apache() {
    local port=$1
    local apache_service
    apache_service=$(get_apache_service)

    local ports_conf
    case "$OS" in
        ubuntu|debian) ports_conf="/etc/apache2/ports.conf" ;;
        centos|rhel|fedora|arch) ports_conf="/etc/httpd/conf/httpd.conf" ;;
        opensuse*|suse) ports_conf="/etc/apache2/listen.conf" ;;
    esac

    if ! grep -qE "^\s*Listen\s+${port}$" "$ports_conf"; then
        echo "Listen ${port}" >> "$ports_conf"
    fi

    local vhost_conf
    case "$OS" in
        ubuntu|debian) vhost_conf="/etc/apache2/sites-available/h5ai.conf" ;;
        centos|rhel|fedora|arch) vhost_conf="/etc/httpd/conf.d/h5ai.conf" ;;
        opensuse*|suse) vhost_conf="/etc/apache2/vhosts.d/h5ai.conf" ;;
    esac

    cat <<EOF > "$vhost_conf"
<VirtualHost *:${port}>
    DocumentRoot ${WEBROOT}
    <Directory "${WEBROOT}">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        a2enmod rewrite
        a2ensite h5ai.conf
        a2dissite 000-default.conf || true
    fi

    systemctl reload "$apache_service"
}

setup_firewall() {
    local port=$1
    if is_installed ufw; then
        ufw allow "${port}/tcp"
        ufw reload
    elif systemctl is-active firewalld &>/dev/null; then
        firewall-cmd --permanent --add-port=${port}/tcp
        firewall-cmd --reload
    elif is_installed iptables; then
        if ! iptables -C INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null; then
            iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
        fi
        if is_installed netfilter-persistent; then
            netfilter-persistent save
        elif is_installed iptables-save; then
            iptables-save > /etc/iptables/rules.v4
        fi
    else
        echo "⚠️ 无防火墙工具，需手动放行端口 $port"
    fi
}

download_h5ai() {
    local url="https://github.com/lrsjng/h5ai/releases/download/v0.30.0/h5ai-0.30.0.zip"
    local output="h5ai.zip"

    if is_installed curl; then
        curl -fsSL --retry 3 -o "$output" "$url"
    elif is_installed wget; then
        wget -q --tries=3 --timeout=15 -O "$output" "$url"
    else
        echo "❌ curl 和 wget 都未安装！"
        return 1
    fi
}

prepare_webroot() {
    mkdir -p "$WEBROOT"
    cd "$WEBROOT" || exit 1

    download_h5ai

    unzip -o h5ai.zip && rm -f h5ai.zip

    if [ ! -d "_h5ai" ]; then
        echo "❌ _h5ai 目录缺失"
        exit 1
    fi

    if [ ! -f "index.php" ]; then
        cp -v "_h5ai/public/index.php" "index.php"
    fi

    for user in www-data apache http nginx; do
        if id "$user" &>/dev/null; then
            chown -R "$user:$user" "$WEBROOT"
            break
        fi
    done
}

get_public_ip() {
    curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 ipinfo.io/ip || echo "无法获取公网 IP"
}

main() {
    install_dependencies
    configure_apache "$PORT"
    prepare_webroot
    setup_firewall "$PORT"

    public_ip=$(get_public_ip)
    echo "✅ 安装完成，请访问：http://${public_ip}:${PORT}/"
}

main
