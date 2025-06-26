#!/bin/bash
# /usr/local/bin/setup-2m-1g-hugepages.sh

echo "=== Setting up hugepages at startup ==="

# Wait a moment for system to be ready
sleep 2

# Create mount points
mkdir -p /mnt/huge1G /mnt/huge2M

# Mount 1GB hugepages for your DPDK application
mount -t hugetlbfs -o pagesize=1G hugetlbfs /mnt/huge1G

# Mount 2MB hugepages for TRex (override default)
umount /dev/hugepages 2>/dev/null || true
mount -t hugetlbfs -o pagesize=2M hugetlbfs /dev/hugepages
mount -t hugetlbfs -o pagesize=2M hugetlbfs /mnt/huge2M

# Verify setup
echo "Hugepage setup complete at $(date):"
echo "1GB pages: $(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/free_hugepages) free"
echo "2MB pages: $(cat /sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages) free"

# Log to syslog
logger "Hugepages configured: 1GB at /mnt/huge1G, 2MB at /dev/hugepages
