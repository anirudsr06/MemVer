/*
 * Performance Benchmark 2: Sibling Fetch Cache Locality
 * 
 * Compares:
 *   1. Sequential Access: Accessing 8 consecutive protected cache lines.
 *      - Siblings for these share L1/L2 groups. Tree node reads should HIT in the Dcache.
 *   2. Random Access: Accessing 8 widely striped protected cache lines.
 *      - Tree nodes are in totally different cache lines. Tree node reads will MISS in the Dcache.
 * 
 * Demonstrates the massive performance advantage of spatial locality.
 */

#include <stdint.h>
#include <stdio.h>

#define PROT_BASE     0x85000000UL
#define UNPROT_BASE   0x84000000UL
#define NUM_LINES     8
#define STRIDE_SEQ    0x40UL    /* 64 bytes - consecutive cache lines */
#define STRIDE_RAND   0x1000UL  /* 4 KB - different pages, diff L1/L2 groups */

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

static inline void evict(uintptr_t addr) {
    uintptr_t set_off = addr & 0xFFFUL;
    volatile uint64_t *c = (volatile uint64_t *)(UNPROT_BASE + set_off);
    volatile uint64_t v = *c; (void)v;
    fence();
}

int main(void) {
    printf("\n===========================================================\n");
    printf("  MVU PERF BENCHMARK 2: Sibling Fetch Cache Locality\n");
    printf("  Lines: %d\n", NUM_LINES);
    printf("===========================================================\n\n");

    /* Warmup: seed the regions */
    for (int i = 0; i < NUM_LINES; i++) {
        volatile uint64_t *p_seq = (volatile uint64_t *)(PROT_BASE + 0x4000UL + i * STRIDE_SEQ);
        volatile uint64_t *p_rnd = (volatile uint64_t *)(PROT_BASE + 0x20000UL + i * STRIDE_RAND);
        *p_seq = 0;
        *p_rnd = 0;
        fence();
        evict((uintptr_t)p_seq);
        evict((uintptr_t)p_rnd);
        nop_wait(10000);
    }

    /* --- 1. Sequential Walk --- */
    printf("  Running Sequential Walk (high locality)...\n");
    // Write and Evict
    for (int i = 0; i < NUM_LINES; i++) {
        volatile uint64_t *p = (volatile uint64_t *)(PROT_BASE + 0x4000UL + i * STRIDE_SEQ);
        *p = i;
        fence();
        evict((uintptr_t)p);
        nop_wait(10000);
    }
    // Measure read miss verify cycles
    uint64_t seq_t0 = read_mcycle();
    for (int i = 0; i < NUM_LINES; i++) {
        volatile uint64_t *p = (volatile uint64_t *)(PROT_BASE + 0x4000UL + i * STRIDE_SEQ);
        volatile uint64_t v = *p; (void)v;
    }
    fence();
    uint64_t seq_t1 = read_mcycle();
    uint64_t seq_cyc = seq_t1 - seq_t0;

    /* --- 2. Random/Striped Walk --- */
    printf("  Running Random/Striped Walk (low locality)...\n");
    // Write and Evict
    for (int i = 0; i < NUM_LINES; i++) {
        volatile uint64_t *p = (volatile uint64_t *)(PROT_BASE + 0x20000UL + i * STRIDE_RAND);
        *p = i;
        fence();
        evict((uintptr_t)p);
        nop_wait(10000);
    }
    // Measure read miss verify cycles
    uint64_t rnd_t0 = read_mcycle();
    for (int i = 0; i < NUM_LINES; i++) {
        volatile uint64_t *p = (volatile uint64_t *)(PROT_BASE + 0x20000UL + i * STRIDE_RAND);
        volatile uint64_t v = *p; (void)v;
    }
    fence();
    uint64_t rnd_t1 = read_mcycle();
    uint64_t rnd_cyc = rnd_t1 - rnd_t0;

    printf("\n  LOCALITY PERFORMANCE BENCHMARK RESULT\n");
    printf("  +----------------------+--------------------+--------------------+\n");
    printf("  | Walk Pattern         | Total Cycle Cost   | Avg Cycles / Line  |\n");
    printf("  +----------------------+--------------------+--------------------+\n");
    printf("  | Sequential (Seq)     | %llu | %llu |\n",
           (unsigned long long)seq_cyc, (unsigned long long)(seq_cyc / NUM_LINES));
    printf("  | Random/Striped (Rnd) | %llu | %llu |\n",
           (unsigned long long)rnd_cyc, (unsigned long long)(rnd_cyc / NUM_LINES));
    printf("  +----------------------+--------------------+--------------------+\n\n");

    if (rnd_cyc > seq_cyc) {
        uint64_t speedup = ((rnd_cyc - seq_cyc) * 100) / seq_cyc;
        printf("  Spatial Locality benefit: Sibling D-Cache hit provides a +%llu%% speedup!\n\n",
               (unsigned long long)speedup);
    } else {
        printf("  No significant locality benefit detected. Verify D-Cache status.\n\n");
    }
    printf("===========================================================\n");

    while(1) asm volatile("wfi");
}
