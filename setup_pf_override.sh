#!/usr/bin/env bash
# Bind your PFs to vfio-pci but still keep mlx5_core/ib_uverbs underneath via driver_override.
# After running this, use testpmd on the PF addresses (17:00.0 & 17:00.1) to get full HW RSS.

set -e
DPDK=~/dpdk-stable-23.11.4
DEVBIND="$DPDK/usertools/dpdk-devbind.py"

PF1="0000:17:00.0"
PF2="0000:17:00.1"

echo "1) Tear down all VFs on the PFs (so no leftover VFs):"
for PF in $PF1 $PF2; do
  if [ -f /sys/bus/pci/devices/$PF/sriov_numvfs ]; then
    echo 0 | sudo tee /sys/bus/pci/devices/$PF/sriov_numvfs
  fi
done

echo "2) Put PFs in switchdev (you already did this, but no harm):"
sudo devlink dev eswitch set pci/$PF1 mode switchdev
sudo devlink dev eswitch set pci/$PF2 mode switchdev

echo "3) Force mlx5_core override so it can bind underneath vfio-pci:"
for PF in $PF1 $PF2; do
  echo -n mlx5_core | sudo tee /sys/bus/pci/devices/$PF/driver_override
done

echo "4) Unbind PFs from any driver and bind to vfio-pci:"
sudo python3 $DEVBIND -u $PF1 $PF2
sudo modprobe vfio-pci
sudo python3 $DEVBIND -b vfio-pci $PF1 $PF2

echo "5) Reload rdma modules so ib_uverbs attaches to the PFs:"
sudo modprobe -r mlx5_ib ib_uverbs mlx5_core || true
sudo modprobe mlx5_core
sudo modprobe mlx5_ib
sudo modprobe ib_uverbs

echo "6) Check you still have your verbs devices:"
ls -l /dev/infiniband/uverbs*

echo
echo "==== Now run testpmd on the PFs to get real HW RSS ===="
echo sudo $DPDK/build/app/dpdk-testpmd -l 8-19 -n 1 \\
echo "  -a $PF1 -a $PF2 --log-level=lib.pmd.net.mlx5,debug -- \\"  
echo "  --rxq=64 --txq=64 -i"
