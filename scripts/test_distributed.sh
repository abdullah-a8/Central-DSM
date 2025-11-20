#!/bin/bash

# CentralDSM Distributed Testing Helper
# This script helps you test DSM between local and cloud VM

set -e

BUILDDIR="build"
TESTDIR="$BUILDDIR/tests"

print_usage() {
    echo "CentralDSM Distributed Testing Helper"
    echo "======================================="
    echo ""
    echo "Usage: $0 [role] [master_ip] [port]"
    echo ""
    echo "Roles:"
    echo "  master         - Run as master (writer)"
    echo "  slave-reader   - Run as slave (reader)"
    echo "  slave-writer   - Run as slave (writer/reader)"
    echo ""
    echo "Arguments:"
    echo "  master_ip      - IP address of master node (only for slave)"
    echo "  port           - Port number (default: 5000)"
    echo ""
    echo "Examples:"
    echo "  # On master machine (local or VM):"
    echo "  $0 master"
    echo "  $0 master 5000"
    echo ""
    echo "  # On slave machine (connects to master at 192.168.1.100):"
    echo "  $0 slave-reader 192.168.1.100"
    echo "  $0 slave-writer 192.168.1.100 5000"
    echo ""
    echo "Setup Instructions:"
    echo "==================="
    echo "1. Build the project on both machines:"
    echo "   make clean && make"
    echo ""
    echo "2. On master machine, find your IP:"
    echo "   hostname -I"
    echo "   # or: ip addr show"
    echo ""
    echo "3. Open firewall on master machine:"
    echo "   sudo ufw allow 5000/tcp  # Ubuntu/Debian"
    echo "   # or: sudo firewall-cmd --add-port=5000/tcp --permanent && sudo firewall-cmd --reload"
    echo ""
    echo "4. Start master first:"
    echo "   ./Scripts/test_distributed.sh master"
    echo ""
    echo "5. Then start slaves (replace MASTER_IP with actual IP):"
    echo "   ./Scripts/test_distributed.sh slave-reader MASTER_IP"
    echo ""
    echo "Network Requirements:"
    echo "- Master must be reachable from slave (check with: ping MASTER_IP)"
    echo "- Port 5000 (or custom port) must be open on master"
    echo "- If master is behind NAT, port forwarding may be needed"
}

# Get local IP addresses
show_local_ips() {
    echo ""
    echo "Your local IP addresses:"
    ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print "  " $2}' || \
    hostname -I | tr ' ' '\n' | grep -v "^$" | sed 's/^/  /'
    echo ""
}

run_master() {
    local port=${1:-5000}
    
    echo "========================================="
    echo "Starting CentralDSM Master Node"
    echo "========================================="
    show_local_ips
    echo "Master will listen on port: $port"
    echo "Waiting for 3 processes (including master)..."
    echo ""
    echo "Press Ctrl+C to stop"
    echo ""
    
    "$TESTDIR/demo_master_writer"
}

run_slave_reader() {
    local master_ip=$1
    local port=${2:-5000}
    
    if [ -z "$master_ip" ]; then
        echo "Error: Master IP address required for slave mode"
        echo ""
        print_usage
        exit 1
    fi
    
    echo "========================================="
    echo "Starting CentralDSM Slave Node (Reader)"
    echo "========================================="
    echo "Connecting to master at: $master_ip:$port"
    echo ""
    echo "Testing connectivity..."
    if ping -c 1 -W 2 "$master_ip" > /dev/null 2>&1; then
        echo "✓ Master is reachable"
    else
        echo "⚠ Warning: Cannot ping master. This might still work if ICMP is blocked."
    fi
    echo ""
    
    # Create a temporary modified slave program
    cat > /tmp/temp_slave_reader.c << EOF
#include <stdio.h>
#include "dsm.h"

int main()
{
    unsigned int nb_proc = 3;
    unsigned int nb_lecture = 5;

    void *base_addr = InitSlave("$master_ip", $port);
    printf("base_addr: %lx\n", (long) base_addr);

    printf("=== Phase 1: Initial Barrier ===\n");
    sync_barrier(nb_proc);

    printf("=== Phase 2: Reading Values ===\n");
    for(unsigned int i = 0; i < nb_lecture; i++) {
        lock_read(base_addr);
        printf("[Read %d] integer = %d\n", i+1, *((int*) (base_addr)));
        printf("[Read %d] string  = %s\n", i+1, (char *)(base_addr + sizeof(int)));
        unlock_read(base_addr);
    }

    printf("=== Phase 3: Final Barrier ===\n");
    sync_barrier(nb_proc);
    
    printf("=== Slave-reader completed successfully ===\n");
    QuitDSM();
    return 0;
}
EOF
    
    echo "Compiling custom slave with master IP: $master_ip"
    gcc -o /tmp/temp_slave_reader /tmp/temp_slave_reader.c \
        -std=c99 -Isrc build/lib/libcentraldsm.a -lpthread
    
    echo "Running slave..."
    echo ""
    /tmp/temp_slave_reader
    
    rm -f /tmp/temp_slave_reader /tmp/temp_slave_reader.c
}

run_slave_writer() {
    local master_ip=$1
    local port=${2:-5000}
    
    if [ -z "$master_ip" ]; then
        echo "Error: Master IP address required for slave mode"
        echo ""
        print_usage
        exit 1
    fi
    
    echo "========================================="
    echo "Starting CentralDSM Slave Node (Writer/Reader)"
    echo "========================================="
    echo "Connecting to master at: $master_ip:$port"
    echo ""
    echo "Testing connectivity..."
    if ping -c 1 -W 2 "$master_ip" > /dev/null 2>&1; then
        echo "✓ Master is reachable"
    else
        echo "⚠ Warning: Cannot ping master. This might still work if ICMP is blocked."
    fi
    echo ""
    
    # Create a temporary modified slave program
    cat > /tmp/temp_slave_writer.c << EOF
#include <stdio.h>
#include <string.h>
#include "dsm.h"

int main()
{
    unsigned int nb_proc = 3;
    unsigned int nb_lecture = 5;
    
    void *base_addr = InitSlave("$master_ip", $port);
    printf("base_addr: %lx\\n", (long) base_addr);

    printf("=== Phase 1: Initial Barrier ===\\n");
    sync_barrier(nb_proc);

    printf("=== Phase 2: Writing String ===\\n");
    lock_write(base_addr);
    strcpy((char *)(base_addr + sizeof(int)), "hello world");
    printf("  Written string: %s\\n", (char *)(base_addr + sizeof(int)));
    unlock_write(base_addr);

    printf("=== Phase 3: Reading Values ===\\n");
    for(unsigned int i = 0; i < nb_lecture; i++) {
        lock_read(base_addr);
        printf("[Read %d] integer = %d\\n", i+1, *((int*) (base_addr)));
        printf("[Read %d] string  = %s\\n", i+1, (char *)(base_addr + sizeof(int)));
        unlock_read(base_addr);
    }

    printf("=== Phase 4: Final Barrier ===\\n");
    sync_barrier(nb_proc);
    
    printf("=== Slave-writer completed successfully ===\\n");
    QuitDSM();
    return 0;
}
EOF
    
    echo "Compiling custom slave with master IP: $master_ip"
    gcc -o /tmp/temp_slave_writer /tmp/temp_slave_writer.c \
        -std=c99 -Isrc build/lib/libcentraldsm.a -lpthread
    
    echo "Running slave..."
    echo ""
    /tmp/temp_slave_writer
    
    rm -f /tmp/temp_slave_writer /tmp/temp_slave_writer.c
}

# Main script logic
if [ $# -eq 0 ]; then
    print_usage
    exit 1
fi

case $1 in
    master)
        run_master "$2"
        ;;
    slave-reader)
        run_slave_reader "$2" "$3"
        ;;
    slave-writer)
        run_slave_writer "$2" "$3"
        ;;
    help|--help|-h)
        print_usage
        ;;
    *)
        echo "Error: Unknown role: $1"
        echo ""
        print_usage
        exit 1
        ;;
esac

