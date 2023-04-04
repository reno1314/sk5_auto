#!/bin/bash
for((i=5;i<=11;i++));do /sbin/ip address add 10.0.0.$i/24 dev eth0;done
/etc/init.d/sockd start

exit
