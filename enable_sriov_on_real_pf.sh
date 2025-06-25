#!/usr/bin/env bash
set -e

# Real PF addresses (not the representors!)
PF1=0000:18:00.0
PF2=0000:18:00.1

DPDK_DIR=~/dpdk-stable-23.11.4
DEVBIND=$DPDK_DIR/usertools/dpdk-devbind.py

echo "1) Enable switchdev on the real PFs"
sudo devlink dev eswitch set pci/$PF1 mode switchdev
sudo devlink dev eswitch set pci/$PF2 mode switchdev

echo "2) Create 4 VFs on each PF"
echo 4 | sudo tee /sys/bus/pci/devices/$PF1/sriov_numvfs
echo 4 | sudo tee /sys/bus/pci/devices/$PF2/sriov_numvfs

echo "3) Reload RDMA stack so PFs get /dev/infiniband/uverbs0 & uverbs1"
sudo modprobe -r mlx5_ib ib_uverbs mlx5_core || true
sudo modprobe mlx5_core
sudo modprobe mlx5_ib
sudo modprobe ib_uverbs

echo "   → Verbs devices now:"
ls -l /dev/infiniband/uverbs*

echo "4) Bind ONLY the 8 new VFs to vfio-pci"
sudo modprobe vfio-pci
# PF1’s VFs: .2–.5, PF2’s VFs: .2–.5 on bus 18:00
sudo python3 $DEVBIND -b vfio-pci \
  0000:18:00.2 0000:18:00.3 0000:18:00.4 0000:18:00.5 \
  0000:18:01.2 0000:18:01.3 0000:18:01.4 0000:18:01.5

echo "5) Now run testpmd on the VFs for full HW RSS:"
echo "   sudo $DPDK_DIR/build/app/dpdk-testpmd -l 8-19 -n 1 \\"
echo "     -a 0000:18:00.2 -a 0000:18:00.3 \\"
echo "     -a 0000:18:00.4 -a 0000:18:00.5 \\"
echo "     -a 0000:18:01.2 -a 0000:18:01.3 \\"
echo "     -a 0000:18:01.4 -a 0000:18:01.5 \\"
echo "     --log-level=lib.pmd.net.mlx5,debug -- \\"
echo "     --rxq=64 --txq=64 -i"
