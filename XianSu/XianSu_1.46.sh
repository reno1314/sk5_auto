#!/bin/bash
sudo yum -y install git
git clone https://github.com/reno1314/wondershaper.git
cd wondershaper
sudo make install
sudo systemctl enable wondershaper.service
wondershaper -c -a eth0
wondershaper -a eth0 -d 1500 -u 1500
echo "@reboot sleep 50 && bash /root/XianSu_ZQ_1.46.sh" >> /var/spool/cron/root

exit
