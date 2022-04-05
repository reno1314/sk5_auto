#!/bin/bash
cd wondershaper
sudo make install
sudo systemctl enable wondershaper.service
wondershaper -c -a eth0
wondershaper -a eth0 -d 1500 -u 1500
echo "@reboot sleep 40 && bash /root/XianSu_ZQ_1.46.sh" >> /var/spool/cron/root

exit
