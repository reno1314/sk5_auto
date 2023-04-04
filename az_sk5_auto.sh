#!/bin/bash

rm -f /root/xnwk_30.sh
rm -f /root/sk5_auto.sh
rm -f /root/install.sh
rm -f /root/install_auto.sh
rm -f /root/install_auto_tcp.sh
rm -f /root/az_sk5_auto.sh
rm -f /root/sk5_auto_XS1.46.sh
rm -f /root/sk5_auto_XS1.52.sh
rm -f /root/XianSu_1.46_S5_auto.sh
rm -f /root/XianSu_1.52_S5_auto.sh
sed -i '/@reboot sleep 35 \&\& bash \/root\/sk5_auto.sh/d' /var/spool/cron/root
crontab -l | grep -v '@reboot sleep 35 && /root/xnwk_30.sh'  | crontab -

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
        for((i=1;i<=14;i++));do /sbin/ip address add 10.0.0.$i/24 dev $NIC;done
        echo "#!/bin/bash" > "$SCRIPT_PATH"
        echo "for((i=5;i<=8;i++));do /sbin/ip address add 10.0.0.$i/24 dev $NIC;done" >> "$SCRIPT_PATH"
        echo "for((i=1;i<=14;i++));do /sbin/ip address add 10.0.0.$i/24 dev $NIC;done" >> "$SCRIPT_PATH"
        echo "sudo /etc/init.d/sockd start" >> "$SCRIPT_PATH"
        echo "exit" >> "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    fi
    (crontab -l 2>/dev/null | grep -v -F -x "@reboot sleep 35 && $SCRIPT_PATH"; echo "@reboot sleep 35 && $SCRIPT_PATH") | crontab -
fi
elif [ "$SYSTEM_RECOGNIZE" == "centos" ]; then
# 判断主网卡的内网地址是否为 10.0.0.*
rm -f /root/xnwk_30.sh
if [[ $IP =~ ^10\.0\.0\..* ]]; then
    # 如果是，则执行以下脚本
    NIC=$(ip link show | awk -F': ' '!/LOOPBACK/ && /^[0-9]+/ {print $2; exit}')
    SCRIPT_PATH="/root/xnwk_30.sh"
    SCRIPT_NAME="xnwk_30.sh"
    if [ -n "$NIC" ] && [ ! -f "$SCRIPT_PATH" ]; then
        for((i=5;i<=8;i++));do /sbin/ip address add 10.0.0.$i/24 dev $NIC;done
        for((i=1;i<=14;i++));do /sbin/ip address add 10.0.0.$i/24 dev $NIC;done
        echo "#!/bin/bash" > "$SCRIPT_PATH"
        echo "for((i=5;i<=8;i++));do /sbin/ip address add 10.0.0.$i/24 dev $NIC;done" >> "$SCRIPT_PATH"
        echo "for((i=1;i<=14;i++));do /sbin/ip address add 10.0.0.$i/24 dev $NIC;done" >> "$SCRIPT_PATH"
        echo "sudo /etc/init.d/sockd start" >> "$SCRIPT_PATH"
        echo "exit" >> "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    fi
    (crontab -l 2>/dev/null | grep -v -F -x "@reboot sleep 35 && $SCRIPT_PATH"; echo "@reboot sleep 35 && $SCRIPT_PATH") | crontab -
fi
else
    echo "Error: Unsupported system."
    exit 1
fi

sudo yum -y install wget && wget --no-check-certificate https://raw.githubusercontent.com/reno1314/danted/master/install_R.sh -O install.sh

rm -f /root/XianSu_1.46_S5_auto.sh
rm -f /root/XianSu_1.52_S5_auto.sh

exit
