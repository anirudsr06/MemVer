/*
 * Bench 2: Cache Miss Read Latency
 *
 * Measures the cycle cost of a single cache-miss read for:
 *   - Unprotected memory (raw DRAM latency)
 *   - Protected memory (DRAM + MVU tree verification)
 *
 * Each iteration: write → evict → wait → timed read.
 * This isolates the per-access MVU verification cost.
 */

#include <stdint.h>
#include <stdio.h>

#define PROT_BASE    0x85000000UL
#define UNPROT_BASE  0x84000000UL
#define NUM_ITERS    200

static inline uint64_t read_mcycle(void) {
    uint64_t v;
    asm volatile("csrr %0, mcycle" : "=r"(v));
    return v;
}

static inline void fence(void) {
    asm volatile("fence rw,rw" ::: "memory");
}

static inline void nop_wait(int n) {
    for (volatile int d = 0; d < n; d++) asm volatile("nop");
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

    printf("\n========================================\n");
    printf("  BENCH 2: Cache Miss Read Latency\n");
    printf("  %d iterations per test\n", NUM_ITERS);
    printf("========================================\n\n");

    /* --- Test addresses --- */
    volatile uint64_t *prot_addr   = (volatile uint64_t *)(PROT_BASE + 0x4000UL);
    volatile uint64_t *unprot_addr = (volatile uint64_t *)(UNPROT_BASE + 0x4000UL);

    /* Conflict addresses for eviction (same cache set, different tag) */
    uintptr_t set_off_p = (uintptr_t)prot_addr & 0xFFFUL;
    uintptr_t set_off_u = (uintptr_t)unprot_addr & 0xFFFUL;
    volatile uint64_t *evict_prot   = (volatile uint64_t *)(UNPROT_BASE + set_off_p);
    volatile uint64_t *evict_unprot = (volatile uint64_t *)(UNPROT_BASE + 0x10000UL + set_off_u);

    /* Warmup: seed the protected address tree */
    *prot_addr = 0;
    fence();
    { volatile uint64_t v = *evict_prot; (void)v; }
    fence();
    nop_wait(20000);

    /* --- Unprotected miss latency --- */
    uint64_t total_unprot = 0;
    for (int i = 0; i < NUM_ITERS; i++) {
        *unprot_addr = (uint64_t)i;
        fence();
        { volatile uint64_t v = *evict_unprot; (void)v; }
        fence();
        nop_wait(5000);

        uint64_t t0 = read_mcycle();
        volatile uint64_t val = *unprot_addr;
        fence();
        uint64_t t1 = read_mcycle();
        (void)val;
        total_unprot += (t1 - t0);
    }

    /* --- Protected miss latency --- */
    trap_count = 0;
    uint64_t total_prot = 0;
    for (int i = 0; i < NUM_ITERS; i++) {
        *prot_addr = (uint64_t)i;
        fence();
        { volatile uint64_t v = *evict_prot; (void)v; }
        fence();
        nop_wait(20000);

        uint64_t t0 = read_mcycle();
        volatile uint64_t val = *prot_addr;
        fence();
        uint64_t t1 = read_mcycle();
        (void)val;
        total_prot += (t1 - t0);
    }

    uint64_t avg_u = total_unprot / NUM_ITERS;
    uint64_t avg_p = total_prot / NUM_ITERS;

    printf("  Unprotected miss: %llu cycles avg\n", (unsigned long long)avg_u);
    printf("  Protected miss:   %llu cycles avg\n", (unsigned long long)avg_p);
    if (avg_p > avg_u)
        printf("  MVU verify cost:  %llu cycles\n", (unsigned long long)(avg_p - avg_u));
    printf("  Traps: %d\n", trap_count);
    printf("========================================\n");

    while(1) asm volatile("wfi");
}
