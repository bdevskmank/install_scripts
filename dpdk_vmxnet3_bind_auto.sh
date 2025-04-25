#!/bin/bash

# Script to bind vmxnet3 interfaces to DPDK
# Usage: ./dpdk_vmxnet3_bind.sh <pci_addr1> <pci_addr2>

# Exit on error
set -e

# DPDK directory - adjust if needed
DPDK_DIR="/root/dpdk-stable-23.11.3/"
DEVBIND="${DPDK_DIR}/usertools/dpdk-devbind.py"
DPDK_DRIVER=vfio-pci


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



ALL_INTERFACES=$(ip -o link show | awk -F': ' '{print $2}')

# Initialize array for suitable interfaces
declare -a SUITABLE_INTERFACES

for INTERFACE in $ALL_INTERFACES; do
    # Skip loopback and virtual/bridge interfaces
    if [[ "$INTERFACE" == "lo" ]]; then
        continue
    fi

    # Check if interface is UP, if not, try to bring it up
    if ! ip link show "$INTERFACE" | grep -q "UP"; then
        echo "- Interface $INTERFACE is DOWN, attempting to bring it UP..."
        if sudo ip link set "$INTERFACE" up; then
            echo "  Successfully brought $INTERFACE UP"
        else
            echo "  Failed to bring $INTERFACE UP, skipping"
            continue
        fi
    fi
    # Check if it's a bridge or virtual interface
    if ip link show "$INTERFACE" | grep -qE 'bridge|virt|tun|tap|docker|veth|vxlan|geneve|gre|bond|team|virbr'; then
        echo "- Skipping $INTERFACE: appears to be a bridge or virtual interface"
        continue
    fi

    # Check if interface has default route
    if ip route | grep default | grep -q "$INTERFACE"; then
        echo "- Skipping $INTERFACE: has a default route"
        continue
    fi

    # Check if interface is managed by Network Manager and exclude it if needed
    if command -v nmcli &> /dev/null && nmcli device show "$INTERFACE" &> /dev/null; then
        if nmcli device show "$INTERFACE" | grep -q "GENERAL.STATE.*connected"; then
            echo "- Skipping $INTERFACE: actively managed by NetworkManager"
            continue
        fi
    fi

    # Check if the interface has an assigned IP (optional check)
    if ! ip addr show dev "$INTERFACE" | grep -q "inet "; then
        echo "- Note: $INTERFACE has no IP address assigned"
    fi

    # This interface meets our criteria
    SUITABLE_INTERFACES+=("$INTERFACE")
    echo "+ Found suitable interface: $INTERFACE"

    # If we have two interfaces, we can stop searching
    if [ ${#SUITABLE_INTERFACES[@]} -eq 2 ]; then
        break
    fi
done

# Check if we found at least two interfaces
if [ ${#SUITABLE_INTERFACES[@]} -lt 2 ]; then
    echo "Error: Could not find two suitable interfaces. Only found ${#SUITABLE_INTERFACES[@]}"

    if [ ${#SUITABLE_INTERFACES[@]} -eq 0 ]; then
        echo "No suitable interfaces found."
    else
        echo "Only found: ${SUITABLE_INTERFACES[0]}"
    fi

    echo "Please check your network configuration or specify interfaces manually."
    exit 1
fi

INTERFACE1="${SUITABLE_INTERFACES[0]}"
INTERFACE2="${SUITABLE_INTERFACES[1]}"


echo "Selected interfaces for DPDK binding:"
echo "1. $INTERFACE1"
echo "2. $INTERFACE2"


echo "Step 2: Getting PCI addresses for the interfaces"
PCI_ADDR1=$(ethtool -i $INTERFACE1 | grep "bus-info" | awk '{print $2}')
PCI_ADDR2=$(ethtool -i $INTERFACE2 | grep "bus-info" | awk '{print $2}')

if [ -z "$PCI_ADDR1" ] || [ -z "$PCI_ADDR2" ]; then
    echo "Error: Could not determine PCI addresses for interfaces"
    exit 1
fi


echo "Step 3: Unbinding interfaces from current driver"
# Using ip command
sudo ip link set $INTERFACE1 down
sudo ip link set $INTERFACE2 down
sudo python3 "${DEVBIND_SCRIPT}" --unbind $PCI_ADDR1
sudo python3 "${DEVBIND_SCRIPT}" --unbind $PCI_ADDR2


echo "Using DPDK driver: $DPDK_DRIVER"
sudo python3 "${DEVBIND_SCRIPT}" --bind=$DPDK_DRIVER $PCI_ADDR1
sudo python3 "${DEVBIND_SCRIPT}" --bind=$DPDK_DRIVER $PCI_ADDR2

sudo python3 "${DEVBIND_SCRIPT}" --status



