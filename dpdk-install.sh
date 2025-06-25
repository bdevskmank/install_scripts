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

cd dpdk-stable-$DPDK_VERSION
meson -Dexamples=all -Denable_drivers=all build
ninja -C build
cd build
sudo ninja install
sudo ldconfig
