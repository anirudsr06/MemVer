/*
 * Test 3: Multi-Level Propagation (4MB Config)
 * Write to protected data, evict, then verify L1, L2, and L3 DRAM nodes all got updated.
 */
#include <stdint.h>
#include <stdio.h>

/*
 * Address 0x85000040: leaf_index = 8, L1 parent = 1
 *   L1[1] → 0x85400008
 *   L2[0] (parent of L1[0..7]) → 0x85480000
 *   L3[0] (parent of L2[0..7]) → 0x85490000
 */
#define PROT_ADDR     ((volatile uint64_t *)0x85000040UL)
#define L1_ADDR       ((volatile uint64_t *)0x85400008UL)
#define L2_ADDR       ((volatile uint64_t *)0x85480000UL)
#define L3_ADDR       ((volatile uint64_t *)0x85490000UL)
#define EVICT_PROT    ((volatile uint64_t *)0x84000040UL)

static inline void fence(void) { asm volatile("fence rw,rw" ::: "memory"); }
static inline void nop_wait(void) {
    for (volatile int i = 0; i < 2000000; i++) asm volatile("nop");
}

/* Evict a specific address from cache by reading a conflicting address */
static inline void evict_addr(uintptr_t addr) {
    uintptr_t set_off = addr & 0xFFFUL;
    volatile uint64_t *c = (volatile uint64_t *)(0x84010000UL + set_off);
    volatile uint64_t v = *c; (void)v;
    fence();
}

int main(void) {
    printf("\n=== TEST 3: Multi-Level Propagation ===\n\n");

    /* Read initial tree state */
    evict_addr((uintptr_t)L1_ADDR); nop_wait();
    evict_addr((uintptr_t)L2_ADDR); nop_wait();
    evict_addr((uintptr_t)L3_ADDR); nop_wait();

    uint64_t l1_before = *L1_ADDR; fence();
    uint64_t l2_before = *L2_ADDR; fence();
    uint64_t l3_before = *L3_ADDR; fence();

    printf("  Before write:\n");
    printf("    L1[1] = 0x%016llx\n", (unsigned long long)l1_before);
    printf("    L2[0] = 0x%016llx\n", (unsigned long long)l2_before);
    printf("    L3[0] = 0x%016llx\n\n", (unsigned long long)l3_before);

    /* Write and evict */
    printf("  Writing 0xAAAABBBBCCCCDDDD to 0x85000040...\n");
    *PROT_ADDR = 0xAAAABBBBCCCCDDDDUL;
    fence();
    volatile uint64_t v = *EVICT_PROT; (void)v;
    fence(); nop_wait();

    /* Read tree nodes after update */
    evict_addr((uintptr_t)L1_ADDR); nop_wait();
    evict_addr((uintptr_t)L2_ADDR); nop_wait();
    evict_addr((uintptr_t)L3_ADDR); nop_wait();

    uint64_t l1_after = *L1_ADDR; fence();
    uint64_t l2_after = *L2_ADDR; fence();
    uint64_t l3_after = *L3_ADDR; fence();

    printf("  After write:\n");
    printf("    L1[1] = 0x%016llx\n", (unsigned long long)l1_after);
    printf("    L2[0] = 0x%016llx\n", (unsigned long long)l2_after);
    printf("    L3[0] = 0x%016llx\n\n", (unsigned long long)l3_after);

    int pass = 1;
    if (l1_before == l1_after) { printf("  FAIL: L1 unchanged\n"); pass = 0; }
    if (l2_before == l2_after) { printf("  FAIL: L2 unchanged\n"); pass = 0; }
    if (l3_before == l3_after) { printf("  FAIL: L3 unchanged\n"); pass = 0; }

    printf("\n%s\n", pass ? "PASS: All DRAM levels (L1, L2, L3) updated." : "FAIL: Some levels missing.");
    printf("========================================\n");
    while(1) asm volatile("wfi");
}
