#!/usr/bin/expect
spawn su root
expect "Password:"
send "mi_ma\r"
/etc/init.d/sockd restart   
 
expect eof
exit

