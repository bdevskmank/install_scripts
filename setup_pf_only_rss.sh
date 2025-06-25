#!/usr/bin/env bash
#
# Bind your PFs with vfio-pci for DPDK I/O,
# but force mlx5_core+ib_uverbs to bind too so you keep the verbs context
# (and thus get real HW RSS hash in mbuf->hash.rss).

set -e

# Adjust these if your PF addresses differ:
PF1=0000:18:00.0
PF2=0000:18:00.1

DPDK_DIR=~/dpdk-stable-23.11.4
DEVBIND=$DPDK_DIR/usertools/dpdk-devbind.py

echo "1) Unbind PFs from any driver"
sudo python3 $DEVBIND -u $PF1 $PF2

echo "2) Override to mlx5_core so it will always bind underneath vfio-pci"
for PF in $PF1 $PF2; do
  echo -n mlx5_core | sudo tee /sys/bus/pci/devices/$PF/driver_override
done

echo "3) Probe the PFs so mlx5_core (and ib_uverbs) actually attach and create uverbsN"
for PF in $PF1 $PF2; do
  echo $PF | sudo tee /sys/bus/pci/drivers_probe
done

echo "   → check verbs devices for PFs:"
ls -l /dev/infiniband/uverbs*

echo "4) Bind PFs to vfio-pci (I/O BARs in VFIO, verbs still in mlx5_core)"
sudo modprobe vfio-pci
sudo python3 $DEVBIND -b vfio-pci $PF1 $PF2

echo "5) Reload RDMA stack so it picks up the PFs with override in place"
sudo modprobe -r mlx5_ib ib_uverbs mlx5_core || true
sudo modprobe mlx5_core
sudo modprobe mlx5_ib
sudo modprobe ib_uverbs

echo "   → verify verbs devices still exist:"
ls -l /dev/infiniband/uverbs*

cat <<EOF

==== Now run testpmd on the PFs to get 64 queues + real HW RSS ====

sudo $DPDK_DIR/build/app/dpdk-testpmd -l 8-19 -n 1 \\
  -a $PF1 -a $PF2 \\
  --log-level=lib.pmd.net.mlx5,debug -- \\
  --rxq=64 --txq=64 -i

EOF
