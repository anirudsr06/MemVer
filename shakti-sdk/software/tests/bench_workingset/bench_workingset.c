/*
 * Bench 4: Working Set Scaling
 *
 * Measures how MVU overhead scales as the number of distinct
 * protected cache lines accessed increases (1, 2, 4, 8, 16).
 *
 * For each working set size, writes to N addresses, evicts them all,
 * waits, then reads them all back (forcing N MVU verifications).
 */

#include <stdint.h>
#include <stdio.h>

#define PROT_BASE    0x85000000UL
#define UNPROT_BASE  0x84000000UL
#define MAX_ADDRS    16
#define STRIDE       0x200UL  /* 512B apart — different L1 groups */
#define NUM_ROUNDS   50

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

static inline void evict(uintptr_t addr) {
    uintptr_t set_off = addr & 0xFFFUL;
    volatile uint64_t *c = (volatile uint64_t *)(UNPROT_BASE + set_off);
    volatile uint64_t v = *c; (void)v;
    fence();
}

/* Warmup: seed tree for all addresses we'll use */
static void warmup(int n) {
    for (int i = 0; i < n; i++) {
        volatile uint64_t *p = (volatile uint64_t *)(PROT_BASE + 0x8000UL + i * STRIDE);
        *p = 0;
        fence();
        evict((uintptr_t)p);
        nop_wait(20000);
    }
    /* Verify all seeded correctly */
    for (int i = 0; i < n; i++) {
        volatile uint64_t *p = (volatile uint64_t *)(PROT_BASE + 0x8000UL + i * STRIDE);
        evict((uintptr_t)p);
        nop_wait(10000);
        volatile uint64_t v = *p; (void)v;
        fence();
    }
}

static uint64_t bench_working_set(int n_addrs) {
    volatile uint64_t *addrs[MAX_ADDRS];
    for (int i = 0; i < n_addrs; i++)
        addrs[i] = (volatile uint64_t *)(PROT_BASE + 0x8000UL + i * STRIDE);

    uint64_t total_read = 0;

    for (int round = 0; round < NUM_ROUNDS; round++) {
        /* Write to all */
        for (int i = 0; i < n_addrs; i++) {
            *addrs[i] = (uint64_t)(round * 100 + i);
        }
        fence();

        /* Evict all */
        for (int i = 0; i < n_addrs; i++) {
            evict((uintptr_t)addrs[i]);
        }
        nop_wait(20000 * n_addrs);

        /* Timed read-back of all */
        uint64_t t0 = read_mcycle();
        for (int i = 0; i < n_addrs; i++) {
            volatile uint64_t val = *addrs[i];
            (void)val;
        }
        fence();
        uint64_t t1 = read_mcycle();
        total_read += (t1 - t0);
    }

    return total_read / NUM_ROUNDS;
}

int main(void) {
    uintptr_t tvec = (uintptr_t)trap_handler & ~(uintptr_t)3;
    asm volatile("csrw mtvec, %0" :: "r"(tvec));

    printf("\n========================================\n");
    printf("  BENCH 4: Working Set Scaling\n");
    printf("  %d rounds per size\n", NUM_ROUNDS);
    printf("========================================\n\n");

    int sizes[] = {1, 2, 4, 8, 16};
    int num_sizes = sizeof(sizes) / sizeof(sizes[0]);

    /* Warmup all addresses */
    warmup(MAX_ADDRS);
    trap_count = 0;

    printf("  %-12s %-16s %-16s\n", "Working Set", "Total Cycles", "Cycles/Access");
    printf("  %-12s %-16s %-16s\n", "-----------", "------------", "-------------");

    for (int s = 0; s < num_sizes; s++) {
        int n = sizes[s];
        uint64_t cyc = bench_working_set(n);
        uint64_t per_access = cyc / n;
        printf("  %-12d %-16llu %-16llu\n",
               n, (unsigned long long)cyc, (unsigned long long)per_access);
    }

    printf("\n  Total traps: %d\n", trap_count);
    printf("========================================\n");

    while(1) asm volatile("wfi");
}
