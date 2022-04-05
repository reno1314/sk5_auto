#!/bin/bash
wget --no-check-certificate https://raw.githubusercontent.com/reno1314/sk5_auto/master/XianSu_ZQ_1.46.sh -O XianSu_ZQ_1.46.sh && chmod +x XianSu_ZQ_1.46.sh
mv /root/XianSu_ZQ_1.46.sh /etc/rc.d/init.d
cd /etc/rc.d/init.d
chkconfig --add XianSu_ZQ_1.46.sh
chkconfig XianSu_ZQ_1.46.sh on
cd /root

sudo yum -y install git
git clone https://github.com/reno1314/wondershaper.git
cd wondershaper
sudo make install
sudo systemctl enable wondershaper.service
wondershaper -c -a eth0
wondershaper -a eth0 -d 1500 -u 1500

exit
