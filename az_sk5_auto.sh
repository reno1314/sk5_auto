   
#!/bin/bash
rm -f /root/sk5_auto.sh
rm -f /root/sk5_auto_XS1.46.sh
rm -f /root/sk5_auto_XS1.52.sh
rm -f /var/spool/cron/root
wget --no-check-certificate https://raw.githubusercontent.com/reno1314/sk5_auto/master/sk5_auto.sh -O sk5_auto.sh && chmod +x sk5_auto.sh
echo "@reboot sleep 35 && bash /root/sk5_auto.sh" >> /var/spool/cron/root

for((i=2;i<=30;i++));do /sbin/ip address add 10.0.0.$i/24 dev eth0;done

wget --no-check-certificate https://raw.githubusercontent.com/reno1314/danted/master/install_R.sh -O install.sh && bash install.sh

exit
