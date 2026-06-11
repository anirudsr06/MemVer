/*
 * Bench 3: Sparse vs Dense Tree Cost
 *
 * Compares MVU overhead when:
 *   - SPARSE: First-ever access to a new region (siblings all zero → skip DRAM fetch)
 *   - DENSE:  Repeated access to a populated region (siblings exist → must fetch)
 *
 * This directly measures the benefit of the sparse bitmap optimization.
 */

#include <stdint.h>
#include <stdio.h>

#define PROT_BASE     0x85000000UL
#define UNPROT_BASE   0x84000000UL
#define NUM_ADDRS     16   /* 16 distinct cache lines */
#define STRIDE        0x200UL /* 512 bytes apart — each in a different L1 sibling group */
#define NUM_ITERS     100

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

/* Evict a protected address by reading from a conflict */
static inline void evict(uintptr_t addr) {
    uintptr_t set_off = addr & 0xFFFUL;
    volatile uint64_t *c = (volatile uint64_t *)(UNPROT_BASE + set_off);
    volatile uint64_t v = *c; (void)v;
    fence();
}

int main(void) {
    uintptr_t tvec = (uintptr_t)trap_handler & ~(uintptr_t)3;
    asm volatile("csrw mtvec, %0" :: "r"(tvec));

    printf("\n========================================\n");
    printf("  BENCH 3: Sparse vs Dense Tree Cost\n");
    printf("  %d addresses x %d iterations\n", NUM_ADDRS, NUM_ITERS);
    printf("========================================\n\n");

    /*
     * SPARSE TEST: Use a far-out region (0x85100000+) that has never been touched.
     * Each write+evict+read forces MVU to walk the tree, but siblings are all zero.
     * With sparse optimization, DRAM fetches should be skipped.
     */
    printf("[SPARSE] First-time accesses to untouched region...\n");
    trap_count = 0;
    uint64_t total_sparse = 0;

    for (int i = 0; i < NUM_ADDRS; i++) {
        volatile uint64_t *addr = (volatile uint64_t *)(PROT_BASE + 0x100000UL + i * STRIDE);

        /* Write and evict → triggers MVU UPDATE */
        *addr = (uint64_t)i;
        fence();
        evict((uintptr_t)addr);
        nop_wait(20000);

        /* Timed read → triggers MVU VERIFY */
        uint64_t t0 = read_mcycle();
        volatile uint64_t val = *addr;
        fence();
        uint64_t t1 = read_mcycle();
        (void)val;
        total_sparse += (t1 - t0);
    }
    int traps_sparse = trap_count;

    /*
     * DENSE TEST: Re-access the same region repeatedly.
     * Now siblings ARE populated, so DRAM fetches are required.
     */
    printf("[DENSE] Repeated accesses to populated region...\n");
    trap_count = 0;
    uint64_t total_dense = 0;

    /* Populate: write to ALL 8 siblings in a group at 0x85002000 */
    for (int s = 0; s < 8; s++) {
        volatile uint64_t *sib = (volatile uint64_t *)(PROT_BASE + 0x2000UL + s * 0x40UL);
        *sib = (uint64_t)(0xAA + s);
        fence();
        evict((uintptr_t)sib);
        nop_wait(20000);
    }

    /* Now measure verify cost for one address in this populated group */
    volatile uint64_t *dense_addr = (volatile uint64_t *)(PROT_BASE + 0x2000UL);
    for (int i = 0; i < NUM_ADDRS; i++) {
        *dense_addr = (uint64_t)(i + 100);
        fence();
        evict((uintptr_t)dense_addr);
        nop_wait(20000);

        uint64_t t0 = read_mcycle();
        volatile uint64_t val = *dense_addr;
        fence();
        uint64_t t1 = read_mcycle();
        (void)val;
        total_dense += (t1 - t0);
    }
    int traps_dense = trap_count;

    uint64_t avg_sparse = total_sparse / NUM_ADDRS;
    uint64_t avg_dense  = total_dense / NUM_ADDRS;

    printf("\n  Sparse avg read: %llu cycles (%d traps)\n",
           (unsigned long long)avg_sparse, traps_sparse);
    printf("  Dense avg read:  %llu cycles (%d traps)\n",
           (unsigned long long)avg_dense, traps_dense);
    if (avg_dense > avg_sparse)
        printf("  Sparse speedup:  %llu cycles saved per access\n",
               (unsigned long long)(avg_dense - avg_sparse));
    printf("========================================\n");

    while(1) asm volatile("wfi");
}
