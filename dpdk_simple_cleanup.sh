#!/bin/bash

# Simple DPDK Cleanup Script
echo "Cleaning up DPDK resources..."

# Kill DPDK processes
sudo pkill -f dpdk  
sudo pkill -f testpmd  
sleep 2

# Clean hugepages
sudo rm -rf /dev/hugepages/r*  

# Clean shared memory
sudo rm -rf /var/run/dpdk/rte/*  
sudo ipcs -m | grep "0x" | awk '{print $2}' | xargs -r sudo ipcrm -m  

# Reset network interfaces (optional - uncomment if needed)
# sudo dpdk-devbind.py --bind=igb 0000:XX:XX.X

echo "DPDK cleanup completed!"
