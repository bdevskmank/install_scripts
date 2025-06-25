#!/bin/bash

# DPDK Memory and Resource Cleanup Script
# Use this script to clean up DPDK resources before restarting your application

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting DPDK cleanup process...${NC}"

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root for proper cleanup${NC}"
        exit 1
    fi
}

# Function to kill DPDK processes
kill_dpdk_processes() {
    echo -e "${YELLOW}Killing DPDK processes...${NC}"
    
    # Kill any running DPDK applications (adjust process names as needed)
    pkill -f "dpdk" 2>/dev/null || true
    pkill -f "testpmd" 2>/dev/null || true
    pkill -f "l2fwd" 2>/dev/null || true
    pkill -f "l3fwd" 2>/dev/null || true
    
    # Add your specific DPDK application name here
    # pkill -f "your_dpdk_app_name" 2>/dev/null || true
    
    # Wait a moment for processes to terminate
    sleep 2
    
    # Force kill if still running
    pkill -9 -f "dpdk" 2>/dev/null || true
    pkill -9 -f "testpmd" 2>/dev/null || true
    
    echo "DPDK processes terminated"
}

# Function to cleanup hugepages
cleanup_hugepages() {
    echo -e "${YELLOW}Cleaning up hugepages...${NC}"
    
    # Remove hugepage files
    if [ -d "/dev/hugepages" ]; then
        rm -rf /dev/hugepages/rtemap_* 2>/dev/null || true
        rm -rf /dev/hugepages/rte_* 2>/dev/null || true
        rm -rf /dev/hugepages/* 2>/dev/null || true
    fi
    
    # Clean up hugepage mount points
    for mount_point in /mnt/huge /mnt/huge-1G /mnt/huge-2M; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            rm -rf "$mount_point"/* 2>/dev/null || true
        fi
    done
    
    echo "Hugepages cleaned up"
}

# Function to reset network interfaces
reset_network_interfaces() {
    echo -e "${YELLOW}Resetting network interfaces...${NC}"
    
    # Check for interfaces bound to DPDK drivers
    if command -v dpdk-devbind.py >/dev/null 2>&1; then
        # Get list of devices bound to DPDK drivers
        BOUND_DEVICES=$(dpdk-devbind.py --status | grep "drv=" | awk '{print $1}' || true)
        
        if [ ! -z "$BOUND_DEVICES" ]; then
            echo "Found DPDK-bound devices: $BOUND_DEVICES"
            
            # Unbind from DPDK drivers and bind back to kernel drivers
            for device in $BOUND_DEVICES; do
                echo "Resetting device: $device"
                dpdk-devbind.py --unbind "$device" 2>/dev/null || true
                
                # Try to bind back to appropriate kernel driver
                # Common kernel drivers: igb, ixgbe, e1000e, i40e, ice
                for driver in igb ixgbe e1000e i40e ice; do
                    if dpdk-devbind.py --bind="$driver" "$device" 2>/dev/null; then
                        echo "Bound $device to $driver"
                        break
                    fi
                done
            done
        fi
    else
        echo "dpdk-devbind.py not found, skipping interface reset"
    fi
    
    echo "Network interfaces reset completed"
}

# Function to cleanup shared memory
cleanup_shared_memory() {
    echo -e "${YELLOW}Cleaning up shared memory...${NC}"
    
    # Remove DPDK shared memory files
    rm -rf /var/run/dpdk/rte/* 2>/dev/null || true
    rm -rf /tmp/dpdk/* 2>/dev/null || true
    
    # Clean up any remaining shared memory segments
    ipcs -m | grep "0x" | awk '{print $2}' | xargs -r ipcrm -m 2>/dev/null || true
    
    # Clean up semaphores
    ipcs -s | grep "0x" | awk '{print $2}' | xargs -r ipcrm -s 2>/dev/null || true
    
    echo "Shared memory cleaned up"
}

# Function to reset CPU isolation (if used)
reset_cpu_isolation() {
    echo -e "${YELLOW}Checking CPU isolation...${NC}"
    
    # Check if isolcpus is set in kernel parameters
    if grep -q "isolcpus" /proc/cmdline; then
        echo "CPU isolation detected in kernel parameters"
        echo "Note: CPU isolation requires reboot to fully reset"
    fi
    
    # Reset CPU governor to default (optional)
    if [ -d "/sys/devices/system/cpu/cpufreq" ]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            if [ -w "$cpu" ]; then
                echo "powersave" > "$cpu" 2>/dev/null || true
            fi
        done
    fi
}

# Function to cleanup UIO/VFIO resources
cleanup_uio_vfio() {
    echo -e "${YELLOW}Cleaning up UIO/VFIO resources...${NC}"
    
    # Remove UIO device files
    rm -rf /dev/uio* 2>/dev/null || true
    
    # Reset VFIO groups if any
    if [ -d "/dev/vfio" ]; then
        for group in /dev/vfio/*; do
            if [ "$group" != "/dev/vfio/vfio" ]; then
                rm -f "$group" 2>/dev/null || true
            fi
        done
    fi
    
    echo "UIO/VFIO resources cleaned up"
}

# Main cleanup function
main() {
    check_root
    
    echo -e "${GREEN}DPDK Cleanup Script${NC}"
    echo "This script will clean up DPDK resources and memory"
    echo
    
    kill_dpdk_processes
    cleanup_hugepages
    reset_network_interfaces
    cleanup_shared_memory
    reset_cpu_isolation
    cleanup_uio_vfio
    
    echo
    echo -e "${GREEN}DPDK cleanup completed successfully!${NC}"
    echo -e "${YELLOW}You can now restart your DPDK application${NC}"
    
    # Optional: Display system status
    echo
    echo "Current hugepage status:"
    cat /proc/meminfo | grep -i huge || echo "No hugepage information available"
    
    echo
    echo "Current network device status:"
    if command -v dpdk-devbind.py >/dev/null 2>&1; then
        dpdk-devbind.py --status-dev net 2>/dev/null || echo "Could not get device status"
    else
        echo "dpdk-devbind.py not available"
    fi
}

# Run main function
main "$@"
