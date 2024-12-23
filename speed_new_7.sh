#!/bin/bash
rm -f /root/control.sh
curl -kLs https://raw.githubusercontent.com/reno1314/sk5_auto/master/speed_limit_each_new_7.sh -o control.sh && chmod +x control.sh && ./control.sh set

cd /root
[ ! -f /var/spool/cron/root ] && touch /var/spool/cron/root
echo "@reboot sleep 40 && bash /root/control.sh set" >> /var/spool/cron/root
