/*
 * Performance Benchmark 3: Working Set Scale & Cache Thrashing
 * 
 * Measures how MVU overhead scales when the size of the working set increases.
 * We test working set sizes from 1 up to 32 cache lines.
 * 
 * As the working set size grows:
 *   - L1/L2/L3 tree nodes are evicted from the D-Cache due to conflicts/capacity limits.
 *   - Sibling fetches begin to miss in the D-Cache, forcing raw memory accesses.
 * 
 * This shows the scalability limit of the current tree memory architecture.
 */

#include <stdint.h>
#include <stdio.h>

#define PROT_BASE     0x85000000UL
#define UNPROT_BASE   0x84000000UL
#define STRIDE        0x400UL   /* 1 KB stride to distribute addresses across sets */
#define NUM_ROUNDS    30
#define MAX_SIZE      32

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

static void warmup_all(void) {
    for (int i = 0; i < MAX_SIZE; i++) {
        volatile uint64_t *p = (volatile uint64_t *)(PROT_BASE + 0x1000UL + i * STRIDE);
        *p = 0;
        fence();
        evict((uintptr_t)p);
        nop_wait(10000);
    }
}

int main(void) {
    printf("\n===========================================================\n");
    printf("  MVU PERF BENCHMARK 3: Working Set Scaling & D-Cache Thrashing\n");
    printf("  Rounds: %d\n", NUM_ROUNDS);
    printf("===========================================================\n\n");

    warmup_all();

    int test_sizes[] = {1, 2, 4, 8, 16, 24, 32};
    int n_tests = sizeof(test_sizes) / sizeof(test_sizes[0]);

    printf("  Starting benchmark scaling rounds...\n\n");
    printf("  +--------------+------------------+-----------------+\n");
    printf("  | Working Set  | Total Read Cycle | Avg Cycles/Line |\n");
    printf("  | (Cache Lines)| (Verify Round)   | (Verify latency)|\n");
    printf("  +--------------+------------------+-----------------+\n");

    for (int t = 0; t < n_tests; t++) {
        int size = test_sizes[t];
        uint64_t total_cycles = 0;

        for (int r = 0; r < NUM_ROUNDS; r++) {
            // 1. Write to size addresses
            for (int i = 0; i < size; i++) {
                volatile uint64_t *p = (volatile uint64_t *)(PROT_BASE + 0x1000UL + i * STRIDE);
                *p = r * 10 + i;
            }
            fence();

            // 2. Evict all to force verify path on read
            for (int i = 0; i < size; i++) {
                volatile uint64_t *p = (volatile uint64_t *)(PROT_BASE + 0x1000UL + i * STRIDE);
                evict((uintptr_t)p);
            }
            nop_wait(20000 * size);

            // 3. Timed read verification loop
            uint64_t t0 = read_mcycle();
            for (int i = 0; i < size; i++) {
                volatile uint64_t *p = (volatile uint64_t *)(PROT_BASE + 0x1000UL + i * STRIDE);
                volatile uint64_t v = *p; (void)v;
            }
            fence();
            uint64_t t1 = read_mcycle();
            total_cycles += (t1 - t0);
        }

        uint64_t avg_total = total_cycles / NUM_ROUNDS;
        uint64_t avg_per_line = avg_total / size;

        printf("  | %d | %llu | %llu |\n", size, (unsigned long long)avg_total, (unsigned long long)avg_per_line);
    }

    printf("  +--------------+------------------+-----------------+\n\n");
    printf("  Observations:\n");
    printf("  - As Working Set increases, conflict misses in Dcache cause sibling\n");
    printf("    fetches to drop out, leading to scaling degradation.\n\n");
    printf("===========================================================\n");

    while(1) asm volatile("wfi");
}
