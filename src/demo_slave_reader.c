#include <stdio.h>

#include "dsm.h"

int main()
{
	unsigned int num_procs = 3;
	unsigned int num_reads = 10;

	void *base_addr = InitSlave("132.227.112.195", 5000);
	printf("base_addr: %lx\n", (long) base_addr);

	sync_barrier(num_procs);
	lock_read(base_addr);

	for(unsigned int i = 0; i < num_reads; i++) {
		lock_read(base_addr);
		printf("integer = %d\n", *((int*) (base_addr)));
		printf("string = %s\n", base_addr + sizeof(int));
		unlock_read(base_addr);
	}

	sync_barrier(num_procs);
	QuitDSM();
	return 0;
}