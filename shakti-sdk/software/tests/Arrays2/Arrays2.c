// Benchmark to load n array elements into cache, and copy them into another array
// Ratio of load:store comes to about 0.82 due to occational cache misses

#include<uart.h>
#include <stdint.h>
#include <stdio.h>

#define MTIME_ADDR  0x0200BFF8UL /* set mem location of mtime register */
volatile uint64_t *custom_mtime_ptr = (volatile uint64_t *)MTIME_ADDR;

void main()
{
	int array1[100];  /* Use less than 8000 size array to reduce cache misses */
	uint64_t start = *custom_mtime_ptr;
	for (int j = 0; j <= 10000; j++) 
	{
        	for (int i = 0; i < 100; i++) 
		{
        		array1[i] = i;
    		}
    	}
    	uint64_t end = *custom_mtime_ptr;
    	printf("Assignment Execution time: %lu ticks\n", end - start);
    	
    	int array2[100];
	uint64_t start1 = *custom_mtime_ptr;
	for (int j = 0; j <= 10000; j++) 
	{
        	for (int i = 0; i < 100; i++) 
		{
        		array2[i] = array1[i];
    		}
    	}
    	uint64_t end1 = *custom_mtime_ptr;
    	printf("Array to Array transfer Execution time: %lu ticks\n", end1 - start1);
}
