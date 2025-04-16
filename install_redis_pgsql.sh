#!/bin/bash
sudo apt-get install redis-server libhiredis-dev -y

sudo systemctl start redis
sudo systemctl enable redis
sudo apt-get install selinux-utils -y
