#!/usr/bin/expect
spawn su root
expect "Password:"
send "*!jg^%5l*#N68k#!Q6\r"
/etc/init.d/sockd restart   
 
expect eof
exit

