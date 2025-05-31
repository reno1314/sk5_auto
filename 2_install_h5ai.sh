#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "❌ 请以 root 用户运行此脚本"
    exit 1
fi

echo "🕒 开始安装部署流程..."

read -rp "请输入要使用的端口号 (例如 12345): " PORT
if [[ ! "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "❌ 端口号必须是 1-65535 的数字！"
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
        echo "❌ 无法识别操作系统！"
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
            echo "更新 apt 源..."
            apt update -qq
            echo "安装软件包：${pkgs[*]}"
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

    # 额外包
    case "$OS" in
        ubuntu|debian)
            install_packages "${common_pkgs[@]}" ufw iptables iptables-persistent
            ;;
        centos|rhel|fedora)
            # CentOS 下 apache 软件包名可能是 httpd
            common_pkgs=(httpd php php-cli php-xml unzip curl wget)
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

    # 添加 Listen 指令前先检查是否存在，避免重复
    if ! grep -qE "^\s*Listen\s+${port}$" "$ports_conf"; then
        echo "添加 Listen ${port} 到 $ports_conf"
        echo "Listen ${port}" >> "$ports_conf"
    else
        echo "端口 ${port} 已存在于 $ports_conf"
    fi

    local vhost_conf
    case "$OS" in
        ubuntu|debian) vhost_conf="/etc/apache2/sites-available/h5ai.conf" ;;
        centos|rhel|fedora|arch) vhost_conf="/etc/httpd/conf.d/h5ai.conf" ;;
        opensuse*|suse) vhost_conf="/etc/apache2/vhosts.d/h5ai.conf" ;;
    esac

    echo "写入虚拟主机配置 $vhost_conf"
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
        echo "启用 Apache rewrite 模块和 h5ai 站点"
        a2enmod rewrite
        a2ensite h5ai.conf
        a2dissite 000-default.conf || true
    fi

    echo "重载 Apache 服务"
    systemctl reload "$apache_service"
}

setup_firewall() {
    local port=$1
    echo "配置防火墙放通端口 ${port}"
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
        echo "⚠️ 无法自动配置防火墙，需手动放行端口 $port"
    fi

    echo "⚠️ 请确认甲骨文云控制台安全组已经允许外部访问端口 $port"
}

download_h5ai() {
    local url="https://github.com/lrsjng/h5ai/releases/download/v0.30.0/h5ai-0.30.0.zip"
    local output="h5ai.zip"

    echo "下载 h5ai 文件管理器..."
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
    echo "准备网站根目录 $WEBROOT"
    mkdir -p "$WEBROOT"
    cd "$WEBROOT" || { echo "❌ 无法进入目录 $WEBROOT"; exit 1; }

    download_h5ai

    unzip -o h5ai.zip && rm -f h5ai.zip

    if [ ! -d "_h5ai" ]; then
        echo "❌ _h5ai 目录缺失"
        exit 1
    fi

    if [ ! -f "index.php" ]; then
        cp -v "_h5ai/public/index.php" "index.php"
    fi

    # 适配常见 web 用户，设置正确权限
    for user in www-data apache http nginx; do
        if id "$user" &>/dev/null; then
            echo "设置 $user 用户拥有 $WEBROOT 目录权限"
            chown -R "$user:$user" "$WEBROOT"
            break
        fi
    done
}

get_public_ip() {
    curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 ipinfo.io/ip || echo "无法获取公网 IP"
}

check_time_sync() {
    # 简单检测系统时间，防止 Apache 报时钟问题
    local local_time=$(date +%s)
    local ntp_time=$(curl -s --head http://google.com | grep ^Date: | cut -d' ' -f3-)
    if [[ -n "$ntp_time" ]]; then
        local ntp_epoch=$(date -d "$ntp_time" +%s)
        local diff=$((local_time - ntp_epoch))
        diff=${diff#-}  # 绝对值
        if (( diff > 3600 )); then
            echo "⚠️ 本机时间与网络时间相差超过 1 小时，请同步系统时间。"
        fi
    fi
}

main() {
    detect_os
    install_dependencies
    configure_apache "$PORT"
    prepare_webroot
    setup_firewall "$PORT"
    check_time_sync

    local public_ip
    public_ip=$(get_public_ip)
    echo "✅ 安装完成，请访问：http://${public_ip}:${PORT}/"
}

main
