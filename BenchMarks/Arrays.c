#include<uart.h>
#include <stdint.h>
#include <stdio.h>

#define MTIME_ADDR  0x0200BFF8UL
volatile uint64_t *custom_mtime_ptr = (volatile uint64_t *)MTIME_ADDR;

void main()
{
	int array1[10000];
	uint64_t start = *custom_mtime_ptr;
	for (int j = 1; j <= 100000; j++) 
	{
        	for (int i = 1; i <= 10000; i++) 
		{
        		array1[i] = i;
    		}
    	}
    	uint64_t end = *custom_mtime_ptr;
    	printf("Assignment Execution time: %lu ticks\n", end - start);
    	
    	int array2[10000];
	uint64_t start1 = *custom_mtime_ptr;
	for (int j = 1; j <= 100000; j++) 
	{
        	for (int i = 1; i <= 10000; i++) 
		{
        		array2[i] = array1[i];
    		}
    	}
    	uint64_t end1 = *custom_mtime_ptr;
    	printf("Array to Array transfer Execution time: %lu ticks\n", end1 - start1);
	while(1);
}
