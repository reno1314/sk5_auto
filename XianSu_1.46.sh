#!/bin/bash
cd /root
touch sk5_auto_XS1.46.sh
chmod +x sk5_auto_XS1.46.sh
cat >>sk5_auto_XS1.46.sh<<EOF
#!/bin/bash
wondershaper -a eth0 -c
wondershaper -a eth0 -d 1500 -u 1500
exit
EOF
chmod +x /etc/rc.d/rc.local
echo "/root/sk5_auto_XS1.46.sh" >> /etc/rc.d/rc.local
cd /root
echo "@reboot sleep 45 && bash /root/sk5_auto_XS1.46.sh" >> /var/spool/cron/root

sudo yum -y install wget
sudo yum -y install git
git clone https://github.com/reno1314/wondershaper.git
cd wondershaper
sudo make install
wondershaper -a eth0 -c
wondershaper -a eth0 -d 1500 -u 1500

exit
