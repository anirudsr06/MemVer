/*
 * Bench 1: Sequential Write Throughput
 *
 * Measures cycles to write N consecutive 64-bit words to:
 *   - Unprotected memory (baseline)
 *   - Protected memory (MVU update path)
 *
 * This shows the raw write throughput penalty of MVU protection.
 */

#include <stdint.h>
#include <stdio.h>

#define PROT_BASE    0x85000000UL
#define UNPROT_BASE  0x84000000UL
#define NUM_WORDS    64   /* 64 words = 8 cache lines */
#define NUM_ITERS    500

static inline uint64_t read_mcycle(void) {
    uint64_t v;
    asm volatile("csrr %0, mcycle" : "=r"(v));
    return v;
}

static inline void fence(void) {
    asm volatile("fence rw,rw" ::: "memory");
}

static void evict_range(uintptr_t base, int num_words) {
    for (int i = 0; i < num_words; i += 8) {
        uintptr_t addr = base + i * 8;
        uintptr_t set_off = addr & 0xFFFUL;
        volatile uint64_t *c = (volatile uint64_t *)(UNPROT_BASE + 0x10000UL + set_off);
        volatile uint64_t v = *c; (void)v;
    }
    fence();
    for (volatile int d = 0; d < 50000; d++) asm volatile("nop");
}

int main(void) {
    volatile uint64_t *prot  = (volatile uint64_t *)PROT_BASE;
    volatile uint64_t *unprot = (volatile uint64_t *)UNPROT_BASE;

    printf("\n========================================\n");
    printf("  BENCH 1: Sequential Write Throughput\n");
    printf("  %d words x %d iterations\n", NUM_WORDS, NUM_ITERS);
    printf("========================================\n\n");

    /* --- Unprotected sequential writes --- */
    fence();
    uint64_t t0 = read_mcycle();
    for (int iter = 0; iter < NUM_ITERS; iter++) {
        for (int i = 0; i < NUM_WORDS; i++)
            unprot[i] = (uint64_t)(iter + i);
        fence();
    }
    uint64_t t1 = read_mcycle();
    uint64_t cyc_unprot = t1 - t0;

    /* --- Protected sequential writes --- */
    fence();
    uint64_t t2 = read_mcycle();
    for (int iter = 0; iter < NUM_ITERS; iter++) {
        for (int i = 0; i < NUM_WORDS; i++)
            prot[i] = (uint64_t)(iter + i);
        fence();
    }
    uint64_t t3 = read_mcycle();
    uint64_t cyc_prot = t3 - t2;

    printf("  Unprotected: %llu cycles (%llu per iter)\n",
           (unsigned long long)cyc_unprot, (unsigned long long)(cyc_unprot / NUM_ITERS));
    printf("  Protected:   %llu cycles (%llu per iter)\n",
           (unsigned long long)cyc_prot, (unsigned long long)(cyc_prot / NUM_ITERS));
    if (cyc_prot > cyc_unprot) {
        uint64_t overhead = ((cyc_prot - cyc_unprot) * 100) / cyc_unprot;
        printf("  Overhead:    %llu%%\n", (unsigned long long)overhead);
    }
    printf("========================================\n");

    while(1) asm volatile("wfi");
}
