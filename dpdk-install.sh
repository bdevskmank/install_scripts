#!/bin/bash

DPDK_VERSION=23.11.4

sudo apt install cpu-checker -y

sudo kvm-ok

sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils wget libssl-dev -y
sudo apt install build-essential meson python3-pyelftools libnuma-dev pkgconf -y


sudo adduser $OS_USER libvirt
sudo adduser $OS_USER kvm

sudo apt install virt-manager -y 

cd /root

wget https://fast.dpdk.org/rel/dpdk-$DPDK_VERSION.tar.xz 
tar xf dpdk-$DPDK_VERSION.tar.xz

cp install_scripts/rte_config.h dpdk-stable-$DPDK_VERSION/config/

cd dpdk-stable-$DPDK_VERSION
meson setup build     -Dexamples=all     -Ddisable_drivers=net/mana     -Dprefix=/usr/local
ninja -C build
cd build
sudo ninja install
sudo ldconfig
