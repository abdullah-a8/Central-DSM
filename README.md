# CentralDSM: Distributed Shared Memory Implementation

A page-based distributed shared memory system implementing transparent memory sharing across networked nodes using hardware-assisted memory protection and a centralized consistency protocol.

## Overview

CentralDSM provides a shared memory abstraction for distributed processes running on different machines. Applications can read and write to a common memory region as if it were local, while the system automatically handles data transfer, synchronization, and consistency maintenance. The implementation uses OS-level memory protection mechanisms to achieve zero-overhead local access and transparent fault handling.

**Key Characteristics:**
- Page-based memory virtualization (4KB pages)
- Master-slave architecture with centralized coordination
- Single-writer/multiple-reader consistency model
- Hardware-assisted memory protection using mprotect
- Binary serialization for efficient network communication
- POSIX-compliant implementation in C

## Architecture

### Master-Slave Model

The system operates with a single master node that coordinates all memory operations and multiple slave nodes that request page access.

**Master Responsibilities:**
- Maintains authoritative state for all pages
- Tracks page ownership and reader lists
- Processes page requests in FIFO order
- Coordinates invalidation protocol
- Manages barrier synchronization

**Slave Responsibilities:**
- Request pages from master as needed
- Maintain local page cache
- Respond to invalidation messages
- Send modified pages back to master

### Core Components

**dsm_t Structure:**
The top-level container managing memory, network connections, and synchronization primitives.

**dsm_memory_t:**
Manages the shared memory region using mmap allocation. Contains an array of page metadata structures, each with mutex protection and condition variables for coordination.

**dsm_page_t:**
Per-page metadata tracking validation state, access permissions, ownership, and request queues. The master maintains additional structures for pending requests and active readers per page.

**Network Layer:**
TCP-based communication using a background daemon thread that monitors connections with select. Messages are serialized using the Binn binary format for platform independence.

## Memory Consistency Protocol

### Single-Writer/Multiple-Reader (SWMR)

The system enforces that a page can have either one writer or multiple readers at any time, never both simultaneously.

**Read Access:**
When a node requests read access, the master checks for write conflicts. If no writer exists, the page is immediately sent and the requester is added to the readers list. Multiple readers can access the same page concurrently.

**Write Access:**
When a node requests write access, the master must first invalidate all existing readers. An INVALIDATE message is sent to each reader, who must acknowledge by marking their local copy invalid and removing access permissions. Once all acknowledgments arrive, the master grants write access and transfers ownership to the writer. The master also invalidates its own local copy.

**Invalidation Protocol:**
The eager invalidation approach ensures all stale copies are removed before granting write access. Readers receive INVALIDATE messages, immediately set their page protection to PROT_NONE, mark the page as invalid, and send INVALIDATE_ACK responses. This guarantees sequential consistency.

**Write-Back Mechanism:**
Unlike typical DSM systems that retain modified pages until eviction, this implementation requires writers to explicitly send modified pages back to the master on unlock_write. This ensures the master always maintains the latest version, simplifying consistency maintenance and facilitating potential fault recovery.

## Communication Protocol

### Message Types

**CONNECT / CONNECT_ACK:**
Initial handshake where slave sends architecture information (bitness, page size) and master responds with compatibility verification and page count.

**LOCKPAGE:**
Request for page access with specified protection level (read or read-write). Queued by master if conflicts exist.

**GIVEPAGE:**
Transfer of page data with access rights. Contains the page payload and permission level being granted.

**INVALIDATE / INVALIDATE_ACK:**
Invalidation request from master to readers and corresponding acknowledgment. Part of the write conflict resolution protocol.

**SYNC_BARRIER / BARRIER_ACK:**
Barrier synchronization request and release. Master counts arrivals and broadcasts release when threshold reached.

**TERMINATE:**
Graceful shutdown notification allowing master to track active clients.

### Message Serialization

Messages are serialized using the Binn library, which provides compact binary encoding with automatic type handling and endianness correction. Each message is prefixed with a 4-byte length field for framing over TCP streams.

The background daemon thread uses select-based multiplexing to handle multiple simultaneous connections. Incoming messages are dispatched to handlers based on message type.

## Operational Flow

### Initialization

**Master Startup:**
Allocates the shared memory region using mmap with read-write permissions. All pages start in a valid state. Creates a TCP listening socket and spawns the message listener daemon. Connects to itself to establish the communication channel.

**Slave Startup:**
Connects to the master's network address. Performs handshake to verify architecture compatibility. Allocates a memory region of identical size but with all pages set to PROT_NONE (inaccessible and invalid). Spawns the message listener daemon to handle incoming messages.

### Read Operation

When a process calls lock_read on an address, the system identifies the containing page and acquires its mutex. If the page is already valid locally, the lock succeeds immediately. If invalid, a LOCKPAGE message is sent to the master requesting read access, and the calling thread waits on a condition variable.

The master receives the request and adds it to the page's request queue. If no write conflict exists, the request is immediately satisfied by sending a GIVEPAGE message containing the page data. The requesting slave is added to the current readers list.

The slave receives the GIVEPAGE message, temporarily sets the page to writable, copies the received data into the local page, sets the page to read-only, marks it as valid, and signals the condition variable to unblock the waiting thread.

### Write Operation

Write requests follow a similar initial flow but require conflict resolution. When the master receives a write request and active readers exist, it sends INVALIDATE messages to all readers.

Each reader processes the invalidation by marking the page invalid, setting protection to PROT_NONE (making it inaccessible), and sending INVALIDATE_ACK. The master removes each acknowledging reader from the current readers list.

Once all acknowledgments arrive and the readers list is empty, the master sends GIVEPAGE with write permission, transfers ownership to the writer, and invalidates its own local copy by setting it to PROT_NONE.

The slave receives the page with write permission, sets the local protection to PROT_READ|PROT_WRITE, and marks it valid. The application can now modify the page.

When unlock_write is called, the modified page is sent back to the master via a GIVEPAGE message, and the local copy is invalidated. This ensures the master always has the current version.

### Barrier Synchronization

The sync_barrier function provides a coordination point for distributed processes. Each process sends a SYNC_BARRIER message to the master specifying how many processes should participate.

The master maintains a list of waiting processes. When the number of arrivals reaches the specified threshold, it broadcasts BARRIER_ACK to all waiters and clears the waiting list. All processes receive the acknowledgment and continue execution past the barrier.

### Termination

During shutdown, each node sends back any pages it owns with write permission, then sends a TERMINATE message. The master decrements its client count and signals when all clients have disconnected. Resources are freed, including mutex and condition variable destruction, memory unmapping, and socket cleanup.

## Design Characteristics

### Hardware-Assisted Protection

The use of mprotect for access control provides transparent fault handling with no software instrumentation overhead. When a process attempts to access an invalid page, the OS generates a fault that triggers the page fetch mechanism automatically.

### Centralized Coordination

Unlike peer-to-peer DSM systems, the centralized master simplifies the consistency protocol and makes the system easier to reason about. This comes at the cost of a single point of failure and potential scalability limitations, but provides strong consistency guarantees with straightforward implementation.

### Request Queuing

The master queues conflicting requests in FIFO order and processes them as conflicts resolve. This prevents starvation and ensures fairness in page access.

### Per-Page Synchronization

Fine-grained locking with separate mutex and condition variables per page allows the background daemon and application threads to safely operate on different pages concurrently, improving parallelism.

### Architecture Verification

The handshake protocol verifies that all nodes have matching page sizes and pointer sizes, preventing subtle corruption issues from heterogeneous architecture mixing.

## API

**Initialization:**
- `InitMaster(port, page_count)` - Initialize as master node
- `InitSlave(host, port)` - Initialize as slave node

**Memory Access:**
- `lock_read(address)` - Acquire read access to page containing address
- `lock_write(address)` - Acquire write access to page containing address
- `unlock_read(address)` - Release read access
- `unlock_write(address)` - Release write access and send page to master

**Synchronization:**
- `sync_barrier(count)` - Wait for specified number of processes at barrier

**Termination:**
- `QuitDSM()` - Clean shutdown and resource deallocation

## Build System

The Makefile produces both static (libdsm.a) and dynamic (libdsm.so) libraries. Demo programs and tests are built against the static library.

**Build targets:**
- `make` - Build all libraries and demos
- `make clean` - Remove build artifacts
- `make lib` - Build libraries only

## Demo Programs

**demo_master_writer:**
Initializes master, writes an integer to shared memory, and waits for slaves using barrier synchronization.

**demo_slave_reader:**
Connects to master, reads the integer written by master, and participates in barrier.

**demo_slave_writer_reader:**
Demonstrates write operations by writing a string and reading it back.

## Comparison to Standard DSM

Traditional distributed shared memory systems typically use peer-to-peer architectures with distributed ownership and hash-based page location. This implementation's centralized approach trades scalability for simplicity and strong consistency.

Standard DSM often implements release or entry consistency for performance, while this system maintains stricter sequential consistency through eager invalidation.

Most DSM systems use lazy invalidation or update propagation, whereas this implementation proactively invalidates readers before granting write access and requires write-back on unlock.

The hardware-assisted memory protection approach is common in modern DSM but contrasts with earlier software-based instrumentation techniques.

## Implementation Notes

The system is designed for educational purposes to demonstrate DSM concepts clearly. It lacks fault tolerance mechanisms, has scalability limitations due to the centralized master, and assumes reliable network communication.

The implementation is POSIX-compliant and Linux-focused, using standard threading, synchronization, and memory management APIs.

Total implementation size is approximately 2000 lines of core DSM code, with an additional 2700 lines for the Binn serialization library.
