#!/bin/bash

# Script to automatically detect and bind two network interfaces to DPDK
# Usage: ./auto_bind_interfaces_to_dpdk.sh <dpdk_utils_path> [hugepage_size]
# hugepage_size can be "2M" (default) or "1G"

set -e  # Exit on error

# Check for correct number of arguments
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <dpdk_utils_path> [hugepage_size]"
    echo "Example: $0 /usr/local/share/dpdk/usertools 1G"
    echo "         $0 /usr/local/share/dpdk/usertools 2M"
    echo "If hugepage_size is not specified, 2M is used by default."
    exit 1
fi

DPDK_UTILS_PATH=$1
DEVBIND_SCRIPT="${DPDK_UTILS_PATH}/dpdk-devbind.py"

# Default hugepage size is 2M if not specified
HUGEPAGE_SIZE=${2:-"2M"}

# Normalize hugepage size parameter
if [[ "$HUGEPAGE_SIZE" == "1G" ]] || [[ "$HUGEPAGE_SIZE" == "1GB" ]]; then
    HUGEPAGE_SIZE="1G"
    HUGEPAGE_SIZE_KB="1048576"  # 1GB in KB
    HUGEPAGE_COUNT="16"         # Number of 1GB pages to allocate per NUMA node
    MOUNT_DIR="/dev/hugepages1G"
elif [[ "$HUGEPAGE_SIZE" == "2M" ]] || [[ "$HUGEPAGE_SIZE" == "2MB" ]]; then
    HUGEPAGE_SIZE="2M"
    HUGEPAGE_SIZE_KB="2048"     # 2MB in KB
    HUGEPAGE_COUNT="2048"       # Number of 2MB pages to allocate per NUMA node
    MOUNT_DIR="/dev/hugepages"
else
    echo "Error: Invalid hugepage size '$HUGEPAGE_SIZE'. Use either '1G' or '2M'."
    exit 1
fi

# Check if the utility exists
if [ ! -f "${DEVBIND_SCRIPT}" ]; then
    echo "Error: DPDK utility script not found at ${DPDK_UTILS_PATH}"
    exit 1
fi

echo "Detecting suitable network interfaces..."

# Get all network interfaces
ALL_INTERFACES=$(ip -o link show | awk -F': ' '{print $2}')

# Initialize array for suitable interfaces
declare -a SUITABLE_INTERFACES

# Check each interface against our criteria
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

echo "Step 1: Setting up ${HUGEPAGE_SIZE} hugepages for DPDK"

# Ensure kernel modules are loaded
echo "Loading necessary kernel modules..."
sudo modprobe hugetlbfs || echo "Warning: hugetlbfs module load failed, may already be built into kernel"

# Create directory for hugepages
sudo mkdir -p "${MOUNT_DIR}"

# Check if hugepages are already mounted
if mount | grep -q "hugetlbfs.*${HUGEPAGE_SIZE}"; then
    echo "Hugepages (${HUGEPAGE_SIZE}) are already mounted"
else
    # Enable hugepages in the kernel if not already enabled
    if [ ! -d "/sys/kernel/mm/hugepages/hugepages-${HUGEPAGE_SIZE_KB}kB" ]; then
        echo "Creating ${HUGEPAGE_SIZE} hugepage support in kernel"
        echo "${HUGEPAGE_SIZE_KB}" | sudo tee /sys/kernel/mm/hugepages/hugepages-${HUGEPAGE_SIZE_KB}kB/nr_hugepages > /dev/null || echo "Warning: Failed to create ${HUGEPAGE_SIZE} hugepage support"
    fi
    
    # Try mounting hugepages with verbose output for debugging
    echo "Mounting hugepages (${HUGEPAGE_SIZE}) at ${MOUNT_DIR}"
    sudo mount -v -t hugetlbfs -o pagesize=${HUGEPAGE_SIZE} none "${MOUNT_DIR}" || {
        # If mount fails, try alternative approaches
        echo "Warning: Failed to mount hugepages with pagesize=${HUGEPAGE_SIZE} option"
        echo "Trying to mount hugepages without pagesize option..."
        sudo mount -t hugetlbfs none "${MOUNT_DIR}" || {
            echo "Warning: Hugepage mounting failed. Continuing without custom hugepages mount."
            echo "Using default hugepages location at /dev/hugepages"
            
            # Check if default hugepages are mounted
            if ! mount | grep -q "hugetlbfs"; then
                echo "Mounting default hugepages"
                sudo mkdir -p /dev/hugepages
                sudo mount -t hugetlbfs none /dev/hugepages || echo "Warning: Default hugepage mounting failed too"
            fi
        }
    }
fi

# Configure hugepages regardless of mount status
echo "Configuring ${HUGEPAGE_SIZE} hugepages..."
# Try to allocate hugepages on node0
if [ -d "/sys/devices/system/node/node0/hugepages/hugepages-${HUGEPAGE_SIZE_KB}kB" ]; then
    echo "Allocating ${HUGEPAGE_COUNT} hugepages (${HUGEPAGE_SIZE} each) on node0"
    echo "${HUGEPAGE_COUNT}" | sudo tee /sys/devices/system/node/node0/hugepages/hugepages-${HUGEPAGE_SIZE_KB}kB/nr_hugepages > /dev/null || {
        echo "Warning: Failed to allocate ${HUGEPAGE_SIZE} hugepages on node0"
    }
# Try system-wide hugepage allocation if node-specific fails
else
    echo "No NUMA node0 found, trying system-wide hugepage allocation"
    if [ -d "/sys/kernel/mm/hugepages/hugepages-${HUGEPAGE_SIZE_KB}kB" ]; then
        echo "${HUGEPAGE_COUNT}" | sudo tee /sys/kernel/mm/hugepages/hugepages-${HUGEPAGE_SIZE_KB}kB/nr_hugepages > /dev/null
    fi
fi

# Try node1 if it exists
if [ -d "/sys/devices/system/node/node1/hugepages/hugepages-${HUGEPAGE_SIZE_KB}kB" ]; then
    echo "Allocating ${HUGEPAGE_COUNT} hugepages (${HUGEPAGE_SIZE} each) on node1"
    echo "${HUGEPAGE_COUNT}" | sudo tee /sys/devices/system/node/node1/hugepages/hugepages-${HUGEPAGE_SIZE_KB}kB/nr_hugepages > /dev/null || echo "Warning: Failed to allocate ${HUGEPAGE_SIZE} hugepages on node1"
fi

# Verify hugepage configuration
echo "Verifying hugepage configuration:"
grep Huge /proc/meminfo
echo "Mounted filesystems:"
mount | grep huge
echo "Hugepage directories:"
ls -la /dev/hugepages* 2>/dev/null || echo "No hugepage directories found"

echo "Step 2: Getting PCI addresses for the interfaces"
PCI_ADDR1=$(ethtool -i $INTERFACE1 | grep "bus-info" | awk '{print $2}')
PCI_ADDR2=$(ethtool -i $INTERFACE2 | grep "bus-info" | awk '{print $2}')

if [ -z "$PCI_ADDR1" ] || [ -z "$PCI_ADDR2" ]; then
    echo "Error: Could not determine PCI addresses for interfaces"
    exit 1
fi

echo "Found PCI addresses:"
echo "$INTERFACE1: $PCI_ADDR1"
echo "$INTERFACE2: $PCI_ADDR2"

echo "Step 3: Unbinding interfaces from current driver"
# Using ip command
sudo ip link set $INTERFACE1 down
sudo ip link set $INTERFACE2 down
sudo python3 "${DEVBIND_SCRIPT}" --unbind $PCI_ADDR1
sudo python3 "${DEVBIND_SCRIPT}" --unbind $PCI_ADDR2

echo "Step 4: Binding interfaces to DPDK driver"
# First try to load the uio_pci_generic module if not loaded
sudo modprobe uio_pci_generic 2>/dev/null || {
    echo "Failed to load uio_pci_generic module. Trying to load igb_uio module..."
    # Try to load the alternative igb_uio if available
    sudo modprobe igb_uio 2>/dev/null || {
        echo "Failed to load igb_uio module as well."
        echo "Trying to load vfio-pci module..."
        sudo modprobe vfio-pci 2>/dev/null || {
            echo "Failed to load any DPDK-compatible modules."
            echo "Please ensure that either uio_pci_generic, igb_uio, or vfio-pci module is available."
            exit 1
        }
        DPDK_DRIVER="vfio-pci"
    }
    [ -z "$DPDK_DRIVER" ] && DPDK_DRIVER="igb_uio"
}
# Use uio_pci_generic by default if no other driver was selected
DPDK_DRIVER=${DPDK_DRIVER:-uio_pci_generic}

echo "Using DPDK driver: $DPDK_DRIVER"
sudo python3 "${DEVBIND_SCRIPT}" --bind=$DPDK_DRIVER $PCI_ADDR1
sudo python3 "${DEVBIND_SCRIPT}" --bind=$DPDK_DRIVER $PCI_ADDR2

echo "Step 5: Verifying binding"
sudo python3 "${DEVBIND_SCRIPT}" --status

echo "Done! Interfaces $INTERFACE1 and $INTERFACE2 have been bound to DPDK."
echo "HugePages configured with ${HUGEPAGE_SIZE} size at ${MOUNT_DIR}"
echo "To revert the changes and bind back to kernel drivers, you can use:"
echo "sudo python3 ${DEVBIND_SCRIPT} --bind=<original_driver> $PCI_ADDR1 $PCI_ADDR2"

# Save binding information for future reference
echo "Saving interface binding information to dpdk_bound_interfaces.log"
{
  echo "# DPDK Interface Binding Log - Generated on $(date)"
  echo "Interface1: $INTERFACE1 (PCI: $PCI_ADDR1)"
  echo "Interface2: $INTERFACE2 (PCI: $PCI_ADDR2)"
  echo "DPDK Driver: $DPDK_DRIVER"
  echo "Hugepages: ${HUGEPAGE_COUNT} x ${HUGEPAGE_SIZE} pages per NUMA node at ${MOUNT_DIR}"
  echo "Command to unbind:"
  echo "sudo python3 ${DEVBIND_SCRIPT} --unbind $PCI_ADDR1 $PCI_ADDR2"
} | sudo tee dpdk_bound_interfaces.log > /dev/null
