#/bin/bash
#Createdby
#DROP UDP Flood
list=`grep nameserver /etc/resolv.conf |awk '{print $NF}'`
for i in $list
do
        iptables -A OUTPUT -p udp -d $i --dport 53 -j ACCEPT
done
systemctl stop firewalld
systemctl mask firewalld
yum install iptables-services
systemctl enable iptables
systemctl restart iptables
service iptables save
iptables -A OUTPUT -p udp -j DROP
service iptables save
