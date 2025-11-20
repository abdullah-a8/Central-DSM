#include <stdio.h>

#include "dsm.h"

int main()
{
	int integer_val = 858;
	int num_procs = 3;
	int num_reads = 5;
	int *val_ptr;

	void *base_addr = InitMaster(5000, 10);
	printf("base_addr: %lx\n", (long) base_addr);
	val_ptr = (int *) base_addr;
	
	printf("=== Phase 1: Writing Integer ===\n");
	lock_write(base_addr);
	(*val_ptr) = integer_val;
	printf("  Written integer: %d\n", *((int*) (base_addr)));
	unlock_write(base_addr);
	
	printf("=== Phase 2: Initial Barrier ===\n");
	sync_barrier(num_procs);

	printf("=== Phase 3: Reading Values ===\n");
	for(unsigned int i = 0; i < num_reads; i++) {
		lock_read(base_addr);
		printf("[Read %d] integer = %d\n", i+1, *((int*) (base_addr)));
		printf("[Read %d] string  = %s\n", i+1, (char *)(base_addr + sizeof(int)));
		unlock_read(base_addr);
	}

	printf("=== Phase 4: Final Barrier ===\n");
	sync_barrier(num_procs);
	
	printf("=== Master completed successfully ===\n");
	QuitDSM();
	return 0;
}