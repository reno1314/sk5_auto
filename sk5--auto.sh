sudo -i
yum -y install wget && wget --no-check-certificate https://raw.github.com/Lozy/danted/master/install.sh -O install.sh && bash install.sh  --port=12479 --user=123 --passwd=123 && /etc/init.d/sockd start

