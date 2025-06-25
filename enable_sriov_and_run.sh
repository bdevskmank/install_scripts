#!/usr/bin/env bash
# 1) Your PF IDs
PF1=0000:17:00.0
PF2=0000:17:00.1

# 2) Make sure switchdev is enabled on both PFs
sudo devlink dev eswitch set pci/$PF1 mode switchdev
sudo devlink dev eswitch set pci/$PF2 mode switchdev

# 3) Create 4 VFs on each PF
echo 4 | sudo tee /sys/bus/pci/devices/$PF1/sriov_numvfs
echo 4 | sudo tee /sys/bus/pci/devices/$PF2/sriov_numvfs

# 4) Reload the RDMA stack so PFs get /dev/infiniband/uverbs0 & uverbs1
sudo modprobe -r mlx5_ib ib_uverbs mlx5_core || true
sudo modprobe mlx5_core
sudo modprobe mlx5_ib
sudo modprobe ib_uverbs

# 5) Confirm you now have 2 uverbs devices (one per PF)
ls -l /dev/infiniband/uverbs*

# 6) Bind ONLY the 8 new VFs to vfio-pci
DPDK_DIR=~/dpdk-stable-23.11.4
DEVBIND=$DPDK_DIR/usertools/dpdk-devbind.py
sudo modprobe vfio-pci

# PF1’s VFs are .2–.5, PF2’s are .6–.9 (assuming contiguous allocation)
sudo python3 $DEVBIND -b vfio-pci \
  0000:17:00.2 0000:17:00.3 0000:17:00.4 0000:17:00.5 \
  0000:17:01.2 0000:17:01.3 0000:17:01.4 0000:17:01.5

# 7) Run testpmd against the VFs
cd $DPDK_DIR
sudo build/app/dpdk-testpmd \
  -l 8-19 -n 1 \
  -a 0000:17:00.2 -a 0000:17:00.3 \
  -a 0000:17:00.4 -a 0000:17:00.5 \
  -a 0000:17:01:2 -a 0000:17:01.3 \
  -a 0000:17:01.4 -a 0000:17:01.5 \
  --log-level=lib.pmd.net.mlx5,debug -- \
  --rxq=64 --txq=64 -i
