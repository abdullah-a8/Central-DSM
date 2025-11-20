#!/bin/bash

# Simple distributed test with just 2 processes (master + 1 slave)
# This avoids the complexity of coordinating 3 processes

cat > /tmp/simple_master.c << 'EOF'
#include <stdio.h>
#include "dsm.h"

int main()
{
    int entier = 42;
    int nb_proc = 2;  // Only 2 processes
    int *entier_ptr;

    void *base_addr = InitMaster(5000, 10);
    printf("Master started. Base address: %lx\n", (long) base_addr);
    entier_ptr = (int *) base_addr;
    
    printf("Master: Acquiring write lock...\n");
    lock_write(base_addr);
    
    printf("Master: Waiting at barrier for %d processes...\n", nb_proc);
    sync_barrier(nb_proc);

    printf("Master: Writing value %d...\n", entier);
    (*entier_ptr) = entier;
    printf("Master: Successfully wrote: %d\n", *entier_ptr);

    unlock_write(base_addr);
    printf("Master: Released write lock\n");

    printf("Master: Waiting at final barrier...\n");
    sync_barrier(nb_proc);
    
    printf("Master: Cleaning up...\n");
    QuitDSM();
    printf("Master: Done!\n");
    return 0;
}
EOF

cat > /tmp/simple_slave.c << 'EOF'
#include <stdio.h>
#include "dsm.h"

int main(int argc, char *argv[])
{
    unsigned int nb_proc = 2;  // Only 2 processes
    
    if (argc < 2) {
        printf("Usage: %s <master_ip>\n", argv[0]);
        return 1;
    }
    
    char *master_ip = argv[1];
    
    void *base_addr = InitSlave(master_ip, 5000);
    printf("Slave connected. Base address: %lx\n", (long) base_addr);

    printf("Slave: Waiting at barrier for %d processes...\n", nb_proc);
    sync_barrier(nb_proc);
    
    printf("Slave: Acquiring read lock...\n");
    lock_read(base_addr);
    
    printf("Slave: Reading value...\n");
    int value = *((int*) base_addr);
    printf("Slave: Read value = %d\n", value);
    
    unlock_read(base_addr);
    printf("Slave: Released read lock\n");

    printf("Slave: Waiting at final barrier...\n");
    sync_barrier(nb_proc);
    
    printf("Slave: Cleaning up...\n");
    QuitDSM();
    printf("Slave: Done!\n");
    return 0;
}
EOF

echo "Compiling simple test programs..."
gcc -o /tmp/simple_master /tmp/simple_master.c -std=c99 -Isrc build/lib/libcentraldsm.a -lpthread
gcc -o /tmp/simple_slave /tmp/simple_slave.c -std=c99 -Isrc build/lib/libcentraldsm.a -lpthread

if [ "$1" == "master" ]; then
    echo "========================================="
    echo "Starting Simple Master (2 processes only)"
    echo "========================================="
    echo ""
    /tmp/simple_master
elif [ "$1" == "slave" ]; then
    if [ -z "$2" ]; then
        echo "Error: Please provide master IP"
        echo "Usage: $0 slave <master_ip>"
        exit 1
    fi
    echo "========================================="
    echo "Starting Simple Slave"
    echo "========================================="
    echo "Connecting to: $2"
    echo ""
    /tmp/simple_slave "$2"
else
    echo "Usage:"
    echo "  $0 master           # Run master"
    echo "  $0 slave <master_ip> # Run slave"
fi

# Cleanup
rm -f /tmp/simple_master /tmp/simple_slave /tmp/simple_master.c /tmp/simple_slave.c

