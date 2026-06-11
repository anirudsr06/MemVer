/*
 * Performance Benchmark 4: Real-world Mixed Workloads
 * 
 * Runs three realistic algorithmic kernels to compare performance:
 *   1. Vector Copy (Stream read & write)
 *   2. Vector Addition (Dual read, single write)
 *   3. Binary Search (Sparse, logarithmic read/jump pattern)
 * 
 * Provides clear percentage overheads for real-world workloads under MVU.
 */

#include <stdint.h>
#include <stdio.h>

#define ARRAY_SIZE    64  /* Fits nicely in protected memory space */
#define NUM_ITERS     200

#define PROT_A        ((volatile uint64_t *)0x85000000UL)
#define PROT_B        ((volatile uint64_t *)0x85001000UL)
#define PROT_C        ((volatile uint64_t *)0x85002000UL)

#define UNPROT_A      ((volatile uint64_t *)0x84000000UL)
#define UNPROT_B      ((volatile uint64_t *)0x84001000UL)
#define UNPROT_C      ((volatile uint64_t *)0x84002000UL)

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

/* Warmup tree seeding for all used pages */
static void warmup(void) {
    for (int i = 0; i < ARRAY_SIZE; i++) {
        PROT_A[i] = i;
        PROT_B[i] = i * 2;
        PROT_C[i] = 0;
    }
    fence();
    nop_wait(50000);
}

int main(void) {
    printf("\n===========================================================\n");
    printf("  MVU PERF BENCHMARK 4: Real-world Mixed Workloads\n");
    printf("  Array Size: %d elements | Iterations: %d\n", ARRAY_SIZE, NUM_ITERS);
    printf("===========================================================\n\n");

    warmup();

    /* ==========================================
     *  Kernel 1: Vector Copy (C = A)
     * ========================================== */
    
    // Unprotected
    fence();
    uint64_t u_copy_t0 = read_mcycle();
    for (int iter = 0; iter < NUM_ITERS; iter++) {
        for (int i = 0; i < ARRAY_SIZE; i++) {
            UNPROT_C[i] = UNPROT_A[i] + iter;
        }
        fence();
    }
    uint64_t u_copy_t1 = read_mcycle();
    uint64_t u_copy_cyc = u_copy_t1 - u_copy_t0;

    // Protected
    fence();
    uint64_t p_copy_t0 = read_mcycle();
    for (int iter = 0; iter < NUM_ITERS; iter++) {
        for (int i = 0; i < ARRAY_SIZE; i++) {
            PROT_C[i] = PROT_A[i] + iter;
        }
        fence();
    }
    uint64_t p_copy_t1 = read_mcycle();
    uint64_t p_copy_cyc = p_copy_t1 - p_copy_t0;


    /* ==========================================
     *  Kernel 2: Vector Addition (C = A + B)
     * ========================================== */

    // Unprotected
    fence();
    uint64_t u_add_t0 = read_mcycle();
    for (int iter = 0; iter < NUM_ITERS; iter++) {
        for (int i = 0; i < ARRAY_SIZE; i++) {
            UNPROT_C[i] = UNPROT_A[i] + UNPROT_B[i] + iter;
        }
        fence();
    }
    uint64_t u_add_t1 = read_mcycle();
    uint64_t u_add_cyc = u_add_t1 - u_add_t0;

    // Protected
    fence();
    uint64_t p_add_t0 = read_mcycle();
    for (int iter = 0; iter < NUM_ITERS; iter++) {
        for (int i = 0; i < ARRAY_SIZE; i++) {
            PROT_C[i] = PROT_A[i] + PROT_B[i] + iter;
        }
        fence();
    }
    uint64_t p_add_t1 = read_mcycle();
    uint64_t p_add_cyc = p_add_t1 - p_add_t0;


    /* ==========================================
     *  Kernel 3: Binary Search
     * ========================================== */
    
    // Unprotected
    fence();
    uint64_t u_search_t0 = read_mcycle();
    volatile uint64_t u_found = 0;
    for (int iter = 0; iter < NUM_ITERS; iter++) {
        uint64_t target = iter % ARRAY_SIZE;
        int low = 0, high = ARRAY_SIZE - 1;
        while (low <= high) {
            int mid = (low + high) / 2;
            uint64_t val = UNPROT_A[mid];
            if (val == target) {
                u_found = val;
                break;
            } else if (val < target) {
                low = mid + 1;
            } else {
                high = mid - 1;
            }
        }
        fence();
    }
    uint64_t u_search_t1 = read_mcycle();
    uint64_t u_search_cyc = u_search_t1 - u_search_t0;

    // Protected
    fence();
    uint64_t p_search_t0 = read_mcycle();
    volatile uint64_t p_found = 0;
    for (int iter = 0; iter < NUM_ITERS; iter++) {
        uint64_t target = iter % ARRAY_SIZE;
        int low = 0, high = ARRAY_SIZE - 1;
        while (low <= high) {
            int mid = (low + high) / 2;
            uint64_t val = PROT_A[mid];
            if (val == target) {
                p_found = val;
                break;
            } else if (val < target) {
                low = mid + 1;
            } else {
                high = mid - 1;
            }
        }
        fence();
    }
    uint64_t p_search_t1 = read_mcycle();
    uint64_t p_search_cyc = p_search_t1 - p_search_t0;


    /* ==========================================
     *  Print Results
     * ========================================== */
    
    uint64_t overhead_copy = ((p_copy_cyc - u_copy_cyc) * 100) / u_copy_cyc;
    uint64_t overhead_add = ((p_add_cyc - u_add_cyc) * 100) / u_add_cyc;
    uint64_t overhead_search = ((p_search_cyc - u_search_cyc) * 100) / u_search_cyc;

    printf("  MIXED WORKLOAD BENCHMARK COMPARISON\n");
    printf("  +-----------------+------------------+------------------+------------+\n");
    printf("  | Kernel          | Unprotected (cyc)| Protected (cyc)  | Overhead %% |\n");
    printf("  +-----------------+------------------+------------------+------------+\n");
    printf("  | Vector Copy     | %llu | %llu | %llu%% |\n",
           (unsigned long long)u_copy_cyc, (unsigned long long)p_copy_cyc, (unsigned long long)overhead_copy);
    printf("  | Vector Add      | %llu | %llu | %llu%% |\n",
           (unsigned long long)u_add_cyc, (unsigned long long)p_add_cyc, (unsigned long long)overhead_add);
    printf("  | Binary Search   | %llu | %llu | %llu%% |\n",
           (unsigned long long)u_search_cyc, (unsigned long long)p_search_cyc, (unsigned long long)overhead_search);
    printf("  +-----------------+------------------+------------------+------------+\n\n");

    printf("  Notes:\n");
    printf("  - Binary Search accesses memory sparsely, highlighting the on-demand\n");
    printf("    verification latency.\n");
    printf("  - Vector Copy/Add test stream throughput with MVU overhead.\n\n");
    printf("===========================================================\n");

    while(1) asm volatile("wfi");
}
