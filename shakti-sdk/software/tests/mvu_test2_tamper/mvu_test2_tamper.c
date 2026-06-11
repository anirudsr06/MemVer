/*
 * Test 2: Tamper Detection
 * Corrupt a tree node → read protected data → expect Load Access Fault.
 */
#include <stdint.h>
#include <stdio.h>

#define PROT_ADDR         ((volatile uint64_t *)0x85000040UL)
#define L1_NODE_ADDR      ((volatile uint64_t *)0x85400000UL)  /* L1[0]: sibling of L1[1] */
#define EVICT_PROT        ((volatile uint64_t *)0x84000040UL)
#define EVICT_TREE        ((volatile uint64_t *)0x85401000UL)

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

    printf("\n=== TEST 2: Tamper Detection ===\n\n");

    /* Seed the tree: write + evict so tree has valid hash */
    printf("  Seeding tree (write + evict to populate L1[1])...\n");
    *PROT_ADDR = 0x1122334455667788UL;
    fence();
    volatile uint64_t v = *EVICT_PROT; (void)v;
    fence(); nop_wait();

    /* Verify read works without fault */
    v = *EVICT_PROT; (void)v;
    fence(); nop_wait();
    trap_fired = 0;
    v = *PROT_ADDR; (void)v;
    fence();
    if (trap_fired) {
        printf("  ERROR: Unexpected trap during valid read (mcause=%llu)\n",
               (unsigned long long)trap_cause);
        printf("FAIL\n");
        while(1) asm volatile("wfi");
    }
    printf("  Valid read succeeded (no trap).\n");

    /* Corrupt L1 tree node */
    printf("  Corrupting L1[0] (sibling) with 0xBADBADBADBADBADB...\n");
    *L1_NODE_ADDR = 0xBADBADBADBADBADBULL;
    fence();
    v = *EVICT_TREE; (void)v;
    fence(); nop_wait();

    /* Evict protected data so next read forces verify */
    v = *EVICT_PROT; (void)v;
    fence(); nop_wait();

    /* Read protected data — should trigger fault */
    printf("  Reading protected data (expect fault)...\n");
    trap_fired = 0;
    trap_cause = 0;
    v = *PROT_ADDR; (void)v;
    fence();

    if (trap_fired && trap_cause == 5) {
        printf("\nPASS: Load Access Fault (mcause=5) — tamper detected!\n");
    } else if (trap_fired) {
        printf("\nPASS (unexpected cause): Trap fired, mcause=%llu\n",
               (unsigned long long)trap_cause);
    } else {
        printf("\nFAIL: No exception — MVU did not detect corruption.\n");
    }

    printf("================================\n");
    while(1) asm volatile("wfi");
}
