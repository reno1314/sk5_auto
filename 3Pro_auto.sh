#!/bin/bash

# Check if user is root
if [ $(id -u) != "0" ]; then
    echo "Error: You must be root to run this script, please use root to install"
    exit 1
fi

# 获取主网卡的内网地址
IP=$(ip addr | grep 'inet ' | grep -Ev 'inet 127|inet 192\.168' | \
            sed "s/[[:space:]]*inet \([0-9.]*\)\/.*/\1/")

SYSTEM_RECOGNIZE=""

if [ -s "/etc/os-release" ];then
    os_name=$(sed -n 's/PRETTY_NAME="\(.*\)"/\1/p' /etc/os-release)

    if [ -n "$(echo ${os_name} | grep -Ei 'Debian|Ubuntu' )" ];then
        printf "Current OS: %s\n" "${os_name}"
        SYSTEM_RECOGNIZE="debian"

    elif [ -n "$(echo ${os_name} | grep -Ei 'CentOS')" ];then
        printf "Current OS: %s\n" "${os_name}"
        SYSTEM_RECOGNIZE="centos"
    else
        printf "Current OS: %s is not support.\n" "${os_name}"
    fi
elif [ -s "/etc/issue" ];then
    if [ -n "$(grep -Ei 'CentOS' /etc/issue)" ];then
        printf "Current OS: %s\n" "$(grep -Ei 'CentOS' /etc/issue)"
        SYSTEM_RECOGNIZE="centos"
    else
        printf "+++++++++++++++++++++++\n"
        cat /etc/issue
        printf "+++++++++++++++++++++++\n"
        printf "[Error] Current OS: is not available to support.\n"
    fi
else
    printf "[Error] (/etc/os-release) OR (/etc/issue) not exist!\n"
    printf "[Error] Current OS: is not available to support.\n"
fi

# Check the system and set the package manager accordingly
if [ "$SYSTEM_RECOGNIZE" == "debian" ] || [ "$SYSTEM_RECOGNIZE" == "ubuntu" ]; then
    apt-get update
    apt-get install -y cron curl psmisc sudo gcc make
# 判断主网卡的内网地址是否为 10.0.0.*
rm -f /root/xnwk_30.sh
if [[ $IP =~ ^10\.0\.0\..* ]]; then
    # 如果是，则执行以下脚本
    # NIC=$(ip -o link show | awk -F': ' '{print $2,$9}' | awk '!/LOOPBACK/ && !seen[$2]++{print $2; exit}')
    NIC=$(ip link show | awk -F': ' '!/LOOPBACK/ && /^[0-9]+/ {print $2; exit}')
    SCRIPT_PATH="/root/xnwk_30.sh"
    SCRIPT_NAME="xnwk_30.sh"
    if [ -n "$NIC" ] && [ ! -f "$SCRIPT_PATH" ]; then
        for((i=5;i<=8;i++));do /sbin/ip address add 10.0.0.$i/24 dev $NIC;done
        for((i=11;i<=15;i++));do /sbin/ip address add 10.0.0.$i/24 dev $NIC;done
        echo "#!/bin/bash" > "$SCRIPT_PATH"
        echo 'for((i=5;i<=8;i++));do /sbin/ip address add 10.0.0.$i/24 dev '"$NIC"';done' >> "$SCRIPT_PATH"
        echo 'for((i=11;i<=15;i++));do /sbin/ip address add 10.0.0.$i/24 dev '"$NIC"';done' >> "$SCRIPT_PATH"
        echo "sudo /etc/init.d/3proxy start" >> "$SCRIPT_PATH"
        echo "exit" >> "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    fi
    (crontab -l 2>/dev/null | grep -v -F -x "@reboot sleep 20 && $SCRIPT_PATH"; echo "@reboot sleep 20 && $SCRIPT_PATH") | crontab -
fi
elif [ "$SYSTEM_RECOGNIZE" == "centos" ]; then
    yum install -y cronie curl psmisc sudo gcc make
# 判断主网卡的内网地址是否为 10.0.0.*
rm -f /root/xnwk_30.sh
if [[ $IP =~ ^10\.0\.0\..* ]]; then
    # 如果是，则执行以下脚本
    NIC=$(ip link show | awk -F': ' '!/LOOPBACK/ && /^[0-9]+/ {print $2; exit}')
    SCRIPT_PATH="/root/xnwk_30.sh"
    SCRIPT_NAME="xnwk_30.sh"
    if [ -n "$NIC" ] && [ ! -f "$SCRIPT_PATH" ]; then
        for((i=5;i<=8;i++));do /sbin/ip address add 10.0.0.$i/24 dev $NIC;done
        for((i=11;i<=15;i++));do /sbin/ip address add 10.0.0.$i/24 dev $NIC;done
        echo "#!/bin/bash" > "$SCRIPT_PATH"
        echo 'for((i=5;i<=8;i++));do /sbin/ip address add 10.0.0.$i/24 dev '"$NIC"';done' >> "$SCRIPT_PATH"
        echo 'for((i=11;i<=15;i++));do /sbin/ip address add 10.0.0.$i/24 dev '"$NIC"';done' >> "$SCRIPT_PATH"
        echo "sudo /etc/init.d/3proxy start" >> "$SCRIPT_PATH"
        echo "exit" >> "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    fi
    (crontab -l 2>/dev/null | grep -v -F -x "@reboot sleep 20 && $SCRIPT_PATH"; echo "@reboot sleep 20 && $SCRIPT_PATH") | crontab -
fi
else
    echo "Error: Unsupported system."
    exit 1
fi

# 下载 3proxy
# wget https://github.com/z3APA3A/3proxy/archive/0.9.4.tar.gz -O 3proxy.tar.gz
curl -L -o 3proxy.tar.gz https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.4.tar.gz

# 解压
tar xvfz 3proxy.tar.gz

# 编译并安装
cd 3proxy-0.9.4
make -f Makefile.Linux
make -f Makefile.Linux install

# 停止3proxy服务
sudo /etc/init.d/3proxy stop

rm -f /etc/3proxy/3proxy.cfg

# 判断主网卡的内网地址是否为 10.0.0.*
if [[ $IP =~ ^10\.0\.0\..* ]]; then
    # 如果是，则执行以下脚本
    # 编辑3proxy配置文件
    cat <<EOF > /etc/3proxy/3proxy.cfg
daemon
pidfile /var/run/3proxy.pid
nserver 8.8.8.8
nserver 8.8.4.4
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65534
setuid 65534
# external 172.26.5.50
# internal 172.26.5.51
auth strong
users 123:CL:123
# socks
# maxconn 65535
socks -p12479 -i10.0.0.4 -e10.0.0.4
socks -p22479 -i10.0.0.5 -e10.0.0.5
socks -p32479 -i10.0.0.6 -e10.0.0.6
socks -p22479 -i10.0.0.11 -e10.0.0.11
socks -p32479 -i10.0.0.12 -e10.0.0.12
flush
EOF
else
    # 如果不是，则执行以下脚本
    # 编辑3proxy配置文件
    cat <<EOF > /etc/3proxy/3proxy.cfg
daemon
pidfile /var/run/3proxy.pid
nserver 8.8.8.8
nserver 8.8.4.4
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65534
setuid 65534
# external 172.26.5.50
# internal 172.26.5.51
auth strong
users 123:CL:123
# socks
# maxconn 65535
socks -p12479
flush
EOF
fi

sudo /etc/init.d/3proxy start

# 判断主网卡的内网地址是否为 10.0.0.*
if [[ $IP =~ ^10\.0\.0\..* ]]; then

    echo "内网地址为 10.0.0.*，准备重启服务器..."
    # 执行重启服务器的命令
    reboot
    exit
else
    echo "内网地址不是 10.0.0.*，退出脚本。"
    exit
fi

exit
