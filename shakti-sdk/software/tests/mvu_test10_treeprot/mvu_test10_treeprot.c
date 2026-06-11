/*
 * Test 10: Tree Region Write Protection
 * Write directly to tree DRAM, then verify that the MVU detects the
 * resulting mismatch when reading the corresponding protected data.
 */
#include <stdint.h>
#include <stdio.h>

#define PROT_ADDR    ((volatile uint64_t *)0x85000000UL)
#define L1_NODE      ((volatile uint64_t *)0x85400000UL)  /* L1[0] */
#define EVICT_PROT   ((volatile uint64_t *)0x84000000UL)
#define EVICT_TREE   ((volatile uint64_t *)0x84010000UL)

static inline void fence(void) { asm volatile("fence rw,rw" ::: "memory"); }
static inline void nop_wait(void) {
    for (volatile int i = 0; i < 2000000; i++) asm volatile("nop");
}

static volatile int trap_fired = 0;
static volatile uint64_t trap_cause = 0;
void __attribute__((interrupt("machine"), aligned(4))) trap_handler(void) {
    trap_fired = 1;
    uint64_t mcause;
    asm volatile("csrr %0, mcause" : "=r"(mcause));
    trap_cause = mcause;
    uint64_t mepc;
    asm volatile("csrr %0, mepc" : "=r"(mepc));
    mepc += 4;
    asm volatile("csrw mepc, %0" :: "r"(mepc));
}

int main(void) {
    uintptr_t tvec = (uintptr_t)trap_handler & ~(uintptr_t)3;
    asm volatile("csrw mtvec, %0" :: "r"(tvec));

    printf("\n=== TEST 10: Tree Region Write Protection ===\n\n");

    /* Seed: write to protected data and evict to populate tree */
    printf("  Seeding tree...\n");
    *PROT_ADDR = 0x1234567890ABCDEFUL;
    fence();
    volatile uint64_t v = *EVICT_PROT; (void)v;
    fence(); nop_wait();

    /* Read to confirm no fault */
    v = *EVICT_PROT; (void)v; fence(); nop_wait();
    trap_fired = 0;
    v = *PROT_ADDR; (void)v; fence();
    if (trap_fired) {
        printf("  ERROR: trap on valid read!\n");
        printf("FAIL\n");
        while(1) asm volatile("wfi");
    }
    printf("  Valid read OK.\n");

    /* Corrupt L1[0] directly */
    printf("  Corrupting L1[0] at 0x85400000...\n");
    *L1_NODE = 0xDEADDEADDEADDEADULL;
    fence();
    v = *EVICT_TREE; (void)v;
    fence(); nop_wait();

    /* Evict protected data and re-read */
    v = *EVICT_PROT; (void)v;
    fence(); nop_wait();

    trap_fired = 0;
    trap_cause = 0;
    v = *PROT_ADDR; (void)v;
    fence();

    if (trap_fired && trap_cause == 5)
        printf("\nPASS: MVU detected tree corruption (mcause=5).\n");
    else if (trap_fired)
        printf("\nPASS (alt cause): trap mcause=%llu\n", (unsigned long long)trap_cause);
    else
        printf("\nFAIL: No trap — MVU missed corruption.\n");

    printf("=============================================\n");
    while(1) asm volatile("wfi");
}
