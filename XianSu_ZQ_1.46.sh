#!/bin/bash
sudo systemctl enable wondershaper.service
wondershaper -c -a eth0
wondershaper -a eth0 -d 1500 -u 1500

exit
