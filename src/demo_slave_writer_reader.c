#include <stdio.h>
#include <string.h>

#include "dsm.h"

int main()
{
	int num_procs = 3;
	char *hello = "Hello world!";
	void *base_addr = InitSlave("132.227.112.195", 5000);

	printf("base_addr: %lx\n", (long) base_addr);

	lock_write(base_addr);
	sync_barrier(num_procs);

	strcpy(base_addr+sizeof(int), hello);
	printf("\tWrite: %s\n", (char *) base_addr+sizeof(int));

	unlock_write(base_addr);

	sync_barrier(num_procs);
	/*lock_read(base_addr);
	printf("\tRead: %d\n",  *((int*) (base_addr)));
	unlock_read(base_addr); */

	QuitDSM();
	return 0;
}