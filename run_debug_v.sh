#!/bin/bash

# Ensure the application is compiled with debug symbols
# make CFLAGS="-g -O0"
gdb -ex "handle SIGSEGV stop print" \
    -ex "set pagination off" \
    -ex "run" \
    -ex "bt full" \
    -ex "frame" \
    -ex "info locals" \
    --args ./skm_skeleton/build/basicfwd-shared \
    -l 5-11 \
    -n 1 \
    --proc-type=primary \
    --huge-dir=/dev/hugepages1G \
    --lb_type=virt \
    --hypervisor_type=vmware \
    --wcore 4 \
    --queue-per-core 1 \
    --working-dir=/mnt/tmp_fs/ \
    --log-level 1
