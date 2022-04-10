#!/bin/bash
rm -f /root/sk5_auto_XS1.46.sh
cd /root
touch sk5_auto_XS1.46.sh
chmod +x sk5_auto_XS1.46.sh
cat >>sk5_auto_XS1.46.sh<<EOF
#!/bin/bash
for((i=2;i<=30;i++));do /sbin/ip address add 10.0.0.$i/24 dev eth0;done
/etc/init.d/sockd start
wondershaper -c -a eth0
wondershaper -a eth0 -d 1540
exit
EOF
chmod +x /etc/rc.d/rc.local
echo "/root/sk5_auto_XS1.46.sh" >> /etc/rc.d/rc.local
cd /root
echo "@reboot sleep 30 && bash /root/sk5_auto_XS1.46.sh" >> /var/spool/cron/root

sudo yum -y install wget
wget --no-check-certificate https://raw.githubusercontent.com/reno1314/danted/master/install_R.sh -O install.sh && bash install.sh  --port=12479 --user=123 --passwd=123 && /etc/init.d/sockd start
sudo yum -y install git
git clone https://github.com/reno1314/wondershaper.git
cd wondershaper
sudo make install
wondershaper -c -a eth0
wondershaper -a eth0 -d 1540

rm -f /root/XianSu_1.46_S5_auto.sh

exit
