#!/bin/bash
for((i=2;i<=30;i++));do /sbin/ip address add 10.0.0.$i/24 dev eth0;done
wget --no-check-certificate https://raw.githubusercontent.com/reno1314/danted/master/install_R.sh -O install.sh && bash install.sh  --port=12479 --user=123 --passwd=123 && /etc/init.d/sockd start

exit
