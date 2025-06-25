#!/usr/bin/env bash
# This script puts the ConnectX-6 PF into switchdev mode so you can drive it with vfio-pci
# while still getting a libibverbs context for DPDK’s mlx5 PMD.

set -e

# Adjust this to your DPDK install location if different
DPDK_DIR="${HOME}/dpdk-stable-23.11.4"
DEVBIND="${DPDK_DIR}/usertools/dpdk-devbind.py"

# Your PF PCI addresses
PF1="0000:17:00.0"
PF2="0000:17:00.1"

echo "==> Step 1: Unbind PFs from any driver"
sudo python3 "$DEVBIND" -u $PF1 $PF2

echo "==> Step 2: Force mlx5_core override so it claims a verbs context under vfio-pci"
for PF in $PF1 $PF2; do
  echo -n "mlx5_core" | sudo tee /sys/bus/pci/devices/$PF/driver_override
done

echo "==> Step 3: Bind PFs to vfio-pci"
sudo modprobe vfio-pci
sudo python3 "$DEVBIND" -b vfio-pci $PF1 $PF2

echo "==> Step 4: Reload the RDMA modules so they attach to the PFs"
sudo modprobe -r mlx5_ib ib_uverbs mlx5_core || true
sudo modprobe mlx5_core
sudo modprobe mlx5_ib
sudo modprobe ib_uverbs

echo "==> Step 5: Verify /dev/infiniband/uverbs* exists for the PFs"
ls -l /dev/infiniband/uverbs*

echo "==> Now run testpmd or your DPDK app against $PF1 and $PF2:"
echo "    sudo ${DPDK_DIR}/build/app/dpdk-testpmd -l 8-19 -n 1 \\"
echo "      -a $PF1 -a $PF2 --log-level=lib.pmd.net.mlx5,debug -- \\"
echo "      --rxq=64 --txq=64 -i"
