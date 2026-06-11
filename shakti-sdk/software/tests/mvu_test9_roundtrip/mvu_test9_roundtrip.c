/*
 * Test 9: Evict-and-Verify Round-Trip
 * Write known patterns, evict, read back, compare values.
 * Core MVU functional test.
 */
#include <stdint.h>
#include <stdio.h>

#define PROT_ADDR    ((volatile uint64_t *)0x85000040UL)
#define EVICT_PROT   ((volatile uint64_t *)0x84000040UL)

static inline void fence(void) { asm volatile("fence rw,rw" ::: "memory"); }
static inline void nop_wait(void) {
    for (volatile int i = 0; i < 2000000; i++) asm volatile("nop");
}

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

    printf("\n=== TEST 9: Evict-and-Verify Round-Trip ===\n\n");

    uint64_t patterns[] = {
        0x0000000000000000UL,
        0xFFFFFFFFFFFFFFFFUL,
        0x5555555555555555UL,
        0xAAAAAAAAAAAAAAAAUL,
        0xDEADBEEFCAFEBABEUL,
        0x0123456789ABCDEFUL,
    };
    int n = sizeof(patterns) / sizeof(patterns[0]);
    int pass = 1;

    for (int i = 0; i < n; i++) {
        *PROT_ADDR = patterns[i];
        fence();

        /* Evict (triggers MVU UPDATE) */
        volatile uint64_t v = *EVICT_PROT; (void)v;
        fence(); nop_wait();

        /* Re-evict so next read is a cache miss (triggers MVU VERIFY) */
        v = *EVICT_PROT; (void)v;
        fence(); nop_wait();

        trap_count = 0;
        uint64_t readback = *PROT_ADDR;
        fence();

        int ok = (readback == patterns[i]) && (trap_count == 0);
        printf("  Pattern 0x%016llx: read=0x%016llx traps=%d %s\n",
               (unsigned long long)patterns[i],
               (unsigned long long)readback,
               trap_count, ok ? "OK" : "FAIL");
        if (!ok) pass = 0;
    }

    printf("\n%s\n", pass ? "PASS" : "FAIL");
    printf("==========================================\n");
    while(1) asm volatile("wfi");
}
