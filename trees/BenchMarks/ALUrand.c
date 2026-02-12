#include<uart.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

#define MTIME_ADDR  0x0200BFF8UL
volatile uint64_t *custom_mtime_ptr = (volatile uint64_t *)MTIME_ADDR;

void main()
{
	uint64_t start = *custom_mtime_ptr;
	int p = 5789;
	int q = 250000;
	int r = 1943;
	int s = 0;
	for (int i = 1; i <= 10000; i++) 
	{
		int a = rand()%4;
		if (a==0) {p = p+i;}
		else if (a==1) {r = r*4;}
		else if (a==2) {q = q-i;}
		else {r = q/i;}
    	}
    	uint64_t end = *custom_mtime_ptr;
    	printf("Execution time: %lu ticks\n", end - start);
	while(1);
}
