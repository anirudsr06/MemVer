/*
 * Test 1: Basic Tree Writeback
 * Write to protected memory → evict → verify tree node in DRAM changed.
 */
#include <stdint.h>
#include <stdio.h>

#define PROT_ADDR         ((volatile uint64_t *)0x85000040UL)
#define L1_NODE_ADDR      ((volatile uint64_t *)0x85400008UL)  /* L1[1]: parent of leaves 8-15 */
#define EVICT_PROT        ((volatile uint64_t *)0x84000040UL)  /* same cache set, diff tag */
#define EVICT_TREE        ((volatile uint64_t *)0x85401000UL)  /* evict tree node cache line */

static inline void fence(void) { asm volatile("fence rw,rw" ::: "memory"); }
static inline void nop_wait(void) {
    for (volatile int i = 0; i < 2000000; i++) asm volatile("nop");
}

int main(void) {
    printf("\n=== TEST 1: Basic Tree Writeback ===\n\n");

    /* Read initial tree node value */
    volatile uint64_t v = *EVICT_TREE; (void)v;  /* ensure tree node not cached */
    fence(); nop_wait();
    uint64_t tree_before = *L1_NODE_ADDR;
    printf("  L1[1] before: 0x%016llx\n", (unsigned long long)tree_before);

    /* Write to protected data */
    printf("  Writing 0xDEADBEEFCAFEBABE to 0x85000040...\n");
    *PROT_ADDR = 0xDEADBEEFCAFEBABEUL;
    fence();

    /* Evict → triggers MVU UPDATE */
    v = *EVICT_PROT; (void)v;
    fence(); nop_wait();

    /* Re-read tree node */
    v = *EVICT_TREE; (void)v;
    fence(); nop_wait();
    uint64_t tree_after = *L1_NODE_ADDR;
    printf("  L1[1] after:  0x%016llx\n\n", (unsigned long long)tree_after);

    if (tree_before != tree_after)
        printf("PASS: Tree memory updated by MVU.\n");
    else
        printf("FAIL: Tree memory unchanged.\n");

    printf("====================================\n");
    while(1) asm volatile("wfi");
}
