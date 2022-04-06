#!/bin/bash
cd /root
touch sk5_auto.sh
chmod +x sk5_auto.sh
cat >>sk5_auto.sh<<EOF
#!/bin/bash
for((i=2;i<=30;i++));do /sbin/ip address add 10.0.0.$i/24 dev eth0;done
/etc/init.d/sockd start
exit
EOF
touch XianSu_ZQ_1.46.sh
chmod +x XianSu_ZQ_1.46.sh
cat >>XianSu_ZQ_1.46.sh<<EOF
#!/bin/bash
wondershaper -a eth0 -c
wondershaper -a eth0 -d 1500 -u 1500
exit
EOF
chmod +x /etc/rc.d/rc.local
echo "/root/sk5_auto.sh" >> /etc/rc.d/rc.local
echo "/root/XianSu_ZQ_1.46.sh" >> /etc/rc.d/rc.local
cd /root
sudo yum -y install wget
wget --no-check-certificate https://raw.githubusercontent.com/reno1314/danted/master/install_R.sh -O install.sh && bash install.sh  --port=12479 --user=123 --passwd=123 && /etc/init.d/sockd start
sudo yum -y install git
git clone https://github.com/reno1314/wondershaper.git
cd wondershaper
sudo make install
wondershaper -a eth0 -c
wondershaper -a eth0 -d 1500 -u 1500

exit
