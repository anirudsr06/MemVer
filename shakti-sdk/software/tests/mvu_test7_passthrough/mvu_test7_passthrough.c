/*
 * Test 7: Unprotected Passthrough
 * Verify unprotected reads/writes bypass MVU with no overhead or faults.
 */
#include <stdint.h>
#include <stdio.h>

#define UNPROT_ADDR  ((volatile uint64_t *)0x84000100UL)
#define NUM_ITERS    100

static inline uint64_t read_mcycle(void) {
    uint64_t v; asm volatile("csrr %0, mcycle" : "=r"(v)); return v;
}
static inline void fence(void) { asm volatile("fence rw,rw" ::: "memory"); }

static volatile int trap_count = 0;
void __attribute__((interrupt("machine"), aligned(4))) trap_handler(void) {
    trap_count++;
    uint64_t mepc;
    asm volatile("csrr %0, mepc" : "=r"(mepc));
    mepc += 4;
    asm volatile("csrw mepc, %0" :: "r"(mepc));
}

int main(void) {
    uintptr_t tvec = (uintptr_t)trap_handler & ~(uintptr_t)3;
    asm volatile("csrw mtvec, %0" :: "r"(tvec));

    printf("\n=== TEST 7: Unprotected Passthrough ===\n\n");

    trap_count = 0;
    fence();
    uint64_t t0 = read_mcycle();
    for (int i = 0; i < NUM_ITERS; i++) {
        *UNPROT_ADDR = (uint64_t)i;
        fence();
        volatile uint64_t v = *UNPROT_ADDR; (void)v;
        fence();
    }
    uint64_t t1 = read_mcycle();

    printf("  %d R/W iterations at 0x84000100 (unprotected)\n", NUM_ITERS);
    printf("  Total cycles: %llu (%llu per iter)\n",
           (unsigned long long)(t1-t0), (unsigned long long)((t1-t0)/NUM_ITERS));
    printf("  Traps: %d\n\n", trap_count);

    if (trap_count == 0)
        printf("PASS: No MVU interference on unprotected memory.\n");
    else
        printf("FAIL: %d unexpected traps.\n", trap_count);

    printf("========================================\n");
    while(1) asm volatile("wfi");
}
