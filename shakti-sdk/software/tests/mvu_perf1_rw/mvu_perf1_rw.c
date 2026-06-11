/*
 * Performance Benchmark 1: Read vs. Write Operations
 * 
 * Measures cycle latency for:
 *   1. Cache Hit Read
 *   2. Cache Hit Write
 *   3. Cache Miss Read (MVU verification)
 *   4. Cache Miss Write/Eviction (MVU update)
 * 
 * Compares Protected vs. Unprotected memory to isolate raw MVU overhead.
 */

#include <stdint.h>
#include <stdio.h>

#define PROT_ADDR     ((volatile uint64_t *)0x85000040UL)
#define UNPROT_ADDR   ((volatile uint64_t *)0x84000040UL)
#define EVICT_PROT    ((volatile uint64_t *)0x84000040UL)  /* same cache set, diff tag */
#define EVICT_UNPROT  ((volatile uint64_t *)0x84010040UL)

#define NUM_ROUNDS    100

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

int main(void) {
    printf("\n===========================================================\n");
    printf("  MVU PERF BENCHMARK 1: Read vs. Write Latency\n");
    printf("  Rounds: %d\n", NUM_ROUNDS);
    printf("===========================================================\n\n");

    /* Warmup tree seeding */
    *PROT_ADDR = 0x1234567890ABCDEFUL;
    fence();
    volatile uint64_t dummy = *EVICT_PROT; (void)dummy;
    fence(); nop_wait(20000);

    uint64_t sum_unprot_hit_r = 0, sum_unprot_hit_w = 0;
    uint64_t sum_prot_hit_r = 0, sum_prot_hit_w = 0;
    uint64_t sum_unprot_miss_r = 0, sum_unprot_miss_w = 0;
    uint64_t sum_prot_miss_r = 0, sum_prot_miss_w = 0;

    for (int i = 0; i < NUM_ROUNDS; i++) {
        /* --- 1. Cache Hits --- */
        
        // Unprotected Hit Write
        uint64_t t0 = read_mcycle();
        *UNPROT_ADDR = i;
        fence();
        uint64_t t1 = read_mcycle();
        sum_unprot_hit_w += (t1 - t0);

        // Unprotected Hit Read
        t0 = read_mcycle();
        volatile uint64_t v = *UNPROT_ADDR; (void)v;
        fence();
        t1 = read_mcycle();
        sum_unprot_hit_r += (t1 - t0);

        // Protected Hit Write
        t0 = read_mcycle();
        *PROT_ADDR = i;
        fence();
        t1 = read_mcycle();
        sum_prot_hit_w += (t1 - t0);

        // Protected Hit Read
        t0 = read_mcycle();
        v = *PROT_ADDR; (void)v;
        fence();
        t1 = read_mcycle();
        sum_prot_hit_r += (t1 - t0);

        /* --- 2. Cache Misses --- */

        // Unprotected Miss Write (Evict old first)
        dummy = *EVICT_UNPROT; (void)dummy; fence();
        t0 = read_mcycle();
        *UNPROT_ADDR = i;
        fence();
        t1 = read_mcycle();
        sum_unprot_miss_w += (t1 - t0);

        // Unprotected Miss Read (Evict first)
        dummy = *EVICT_UNPROT; (void)dummy; fence();
        t0 = read_mcycle();
        v = *UNPROT_ADDR; (void)v;
        fence();
        t1 = read_mcycle();
        sum_unprot_miss_r += (t1 - t0);

        // Protected Miss Write / Eviction (triggers MVU Update)
        t0 = read_mcycle();
        dummy = *EVICT_PROT; (void)dummy;
        fence();
        t1 = read_mcycle();
        sum_prot_miss_w += (t1 - t0);
        nop_wait(20000); // wait for update walk to finish

        // Protected Miss Read (triggers MVU Verify)
        t0 = read_mcycle();
        v = *PROT_ADDR; (void)v;
        fence();
        t1 = read_mcycle();
        sum_prot_miss_r += (t1 - t0);
    }

    uint64_t u_hit_r = sum_unprot_hit_r / NUM_ROUNDS;
    uint64_t u_hit_w = sum_unprot_hit_w / NUM_ROUNDS;
    uint64_t p_hit_r = sum_prot_hit_r / NUM_ROUNDS;
    uint64_t p_hit_w = sum_prot_hit_w / NUM_ROUNDS;

    uint64_t u_miss_r = sum_unprot_miss_r / NUM_ROUNDS;
    uint64_t u_miss_w = sum_unprot_miss_w / NUM_ROUNDS;
    uint64_t p_miss_r = sum_prot_miss_r / NUM_ROUNDS;
    uint64_t p_miss_w = sum_prot_miss_w / NUM_ROUNDS;

    printf("  PERFORMANCE COMPARISON TABLE (Average Cycles)\n");
    printf("  +---------------------+-------------+-----------+-----------------+\n");
    printf("  | Operation           | Unprotected | Protected | MVU Cost/Diff   |\n");
    printf("  +---------------------+-------------+-----------+-----------------+\n");
    printf("  | Cache Hit Read      | %llu | %llu | %lld |\n",
           (unsigned long long)u_hit_r, (unsigned long long)p_hit_r, (long long)(p_hit_r - u_hit_r));
    printf("  | Cache Hit Write     | %llu | %llu | %lld |\n",
           (unsigned long long)u_hit_w, (unsigned long long)p_hit_w, (long long)(p_hit_w - u_hit_w));
    printf("  | Cache Miss Read     | %llu | %llu | %lld |\n",
           (unsigned long long)u_miss_r, (unsigned long long)p_miss_r, (long long)(p_miss_r - u_miss_r));
    printf("  | Cache Miss Write    | %llu | %llu | %lld |\n",
           (unsigned long long)u_miss_w, (unsigned long long)p_miss_w, (long long)(p_miss_w - u_miss_w));
    printf("  +---------------------+-------------+-----------+-----------------+\n\n");

    printf("  Observations:\n");
    printf("  - Cache Hit paths should have nearly identical latency (~0 overhead).\n");
    printf("  - Cache Miss Read cost includes fetching siblings and tree hashing.\n");
    printf("  - Cache Miss Write cost shows the eviction latency penalty.\n\n");
    printf("===========================================================\n");

    while(1) asm volatile("wfi");
}
