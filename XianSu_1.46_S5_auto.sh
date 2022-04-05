#!/bin/bash
wget --no-check-certificate https://raw.githubusercontent.com/reno1314/danted/master/install_R.sh -O install.sh && bash install.sh  --port=12479 --user=123 --passwd=123 && /etc/init.d/sockd start
wget --no-check-certificate https://raw.githubusercontent.com/reno1314/sk5_auto/master/sk5_auto.sh -O sk5_auto.sh && chmod +x sk5_auto.sh
chmod +x /etc/rc.d/rc.local
echo "/root/sk5_auto.sh" >> /etc/rc.d/rc.local
wget --no-check-certificate https://raw.githubusercontent.com/reno1314/sk5_auto/master/XianSu_ZQ_1.46.sh -O XianSu_ZQ_1.46.sh && chmod +x XianSu_ZQ_1.46.sh
chmod +x /etc/rc.d/rc.local
echo "/root/XianSu_ZQ_1.46.sh" >> /etc/rc.d/rc.local
sudo yum -y install git
git clone https://github.com/reno1314/wondershaper.git
cd wondershaper
sudo make install
wondershaper -a eth0 -c
wondershaper -a eth0 -d 1500 -u 1500

exit
