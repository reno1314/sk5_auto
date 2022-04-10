#!/bin/bash
cd /root
touch sk5_auto_XS1.46.sh
chmod +x sk5_auto_XS1.46.sh
cat >>sk5_auto_XS1.46.sh<<EOF
#!/bin/bash
wondershaper -c -a eth0
wondershaper -a eth0 -d 1540 -u 1540
exit
EOF
chmod +x /etc/rc.d/rc.local
echo "/root/sk5_auto_XS1.46.sh" >> /etc/rc.d/rc.local
cd /root
echo "@reboot sleep 30 && bash /root/sk5_auto_XS1.46.sh" >> /var/spool/cron/root

sudo yum -y install wget
sudo yum -y install git
git clone https://github.com/reno1314/wondershaper.git
cd wondershaper
sudo make install
wondershaper -c -a eth0
wondershaper -a eth0 -d 1540 -u 1540

exit
