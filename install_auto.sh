#!/bin/bash
rm -f /root/sk5_auto.sh
rm -f /root/sk5_auto_XS1.46.sh
rm -f /root/sk5_auto_XS1.52.sh
cd /root
touch /root/sk5_auto_XS1.52.sh
chmod +x /root/sk5_auto_XS1.52.sh
cat >>/root/sk5_auto_XS1.52.sh<<EOF
#!/bin/bash
for((i=2;i<=30;i++));do /sbin/ip address add 10.0.0.$i/24 dev eth0;done
/etc/init.d/sockd start
exit
EOF
cd /root

rm -f /etc/rc.d/rc.local
touch /etc/rc.d/rc.local
chmod +x /etc/rc.d/rc.local
cat >>/etc/rc.d/rc.local<<EOF
#!/bin/bash
touch /var/lock/subsys/local
/root/sk5_auto_XS1.52.sh
exit
EOF
cd /root
rm -f /var/spool/cron/root
touch /var/spool/cron/root
echo "@reboot sleep 35 && bash /root/sk5_auto_XS1.52.sh" >> /var/spool/cron/root

for((i=2;i<=30;i++));do /sbin/ip address add 10.0.0.$i/24 dev eth0;done
sudo yum -y install wget
wget --no-check-certificate https://raw.githubusercontent.com/reno1314/danted/master/install_R.sh -O install.sh && bash install.sh  --port=12479 --user=123 --passwd=123 && /etc/init.d/sockd start

rm -f /root/XianSu_1.46_S5_auto.sh

exit
