#!/bin/bash
rm -f /root/sk5_auto.sh
rm -f /root/install_auto.sh
rm -f /root/az_sk5_auto.sh
rm -f /root/sk5_auto_XS1.46.sh
rm -f /root/sk5_auto_XS1.52.sh
rm -f /root/XianSu_1.46_S5_auto.sh
rm -f /root/XianSu_1.52_S5_auto.sh
rm -f /root/install.sh

cd /root
touch /root/sk5_auto.sh
chmod a+x /root/sk5_auto.sh
cat >>/root/sk5_auto.sh<<EOF
#!/bin/bash
for((i=2;i<=30;i++));do /sbin/ip address add 10.0.0.$i/24 dev eth0;done
/etc/init.d/sockd start
exit
EOF

sed -i '2c for((i=2;i<=30;i++));do /sbin/ip address add 10.0.0.$i/24 dev eth0;done' /root/sk5_auto.sh

cd /root
rm -f /var/spool/cron/root
touch /var/spool/cron/root
echo "@reboot sleep 35 && bash /root/sk5_auto.sh" >> /var/spool/cron/root

for((i=2;i<=30;i++));do /sbin/ip address add 10.0.0.$i/24 dev eth0;done

exit
