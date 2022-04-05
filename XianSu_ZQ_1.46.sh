#!/bin/bash
#chkconfig: 2345 80 90
#description:auto_run
wondershaper -c -a eth0
wondershaper -a eth0 -d 1500 -u 1500

exit
