#!/bin/bash

# Script to bind vmxnet3 interfaces to DPDK
# Usage: ./dpdk_vmxnet3_bind.sh <pci_addr1> <pci_addr2>

# Exit on error
set -e

# DPDK directory - adjust if needed
DPDK_DIR="/root/dpdk-stable-23.11.3/"
DEVBIND="${DPDK_DIR}/usertools/dpdk-devbind.py"

# Check if PCI addresses are provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <pci_addr1> [pci_addr2]"
    echo "Example: $0 0000:03:00.0 0000:04:00.0"
    echo ""
    echo "Current vmxnet3 interfaces:"
    ${DEVBIND} --status-dev net | grep vmxnet3
    exit 1
fi

# Configure VFIO for no-IOMMU mode (required for VMware)
if [ -f /sys/module/vfio/parameters/enable_unsafe_noiommu_mode ]; then
    echo "Enabling VFIO no-IOMMU mode..."
    echo 1 > /sys/module/vfio/parameters/enable_unsafe_noiommu_mode
else
    echo "VFIO module not loaded correctly. Loading now..."
    modprobe vfio enable_unsafe_noiommu_mode=1
fi

# Load required kernel modules
modprobe vfio-pci

# Bind each provided PCI address
for pci_addr in "$@"; do
    echo "Binding $pci_addr to DPDK..."
    
    # Unbind from current driver if needed
    if [ -e /sys/bus/pci/devices/${pci_addr}/driver ]; then
        echo "Unbinding from current driver..."
        echo ${pci_addr} > /sys/bus/pci/devices/${pci_addr}/driver/unbind
    fi
    
    # Bind to vfio-pci (preferred for VMware vmxnet3)
    ${DEVBIND} --bind=vfio-pci ${pci_addr}
done

echo "DPDK binding complete. Current status:"
${DEVBIND} --status-dev net
