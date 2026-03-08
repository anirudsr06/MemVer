/*
 * MVU Performance Benchmark
 *
 * Measures cycle counts for:
 *   A) Baseline read/write to UNPROTECTED memory (no MVU overhead)
 *   B) Read/write to PROTECTED memory (cache-hot, MVU on first miss only)
 *   C) Protected read after forced eviction (full MVU tree walk each read)
 *   D) Unprotected read after eviction (eviction cost baseline)
 *
 * Uses mcycle CSR for cycle counting.
 *
 * Memory Map:
 *   Protected:   0x85000000 - 0x851FFFFF (2 MB)
 *   Unprotected: 0x84000000 - 0x84FFFFFF (DRAM, no MVU)
 *   Eviction conflicts use 0x84xxxxxx (outside protected region)
 */

#include <stdint.h>
#include <stdio.h>

/* ---- Addresses ---- */
#define PROT_BASE     0x85000000UL
#define UNPROT_BASE   0x84000000UL
#define EVICT_STRIDE  0x1000UL  /* 4 KB */

#define NUM_ITERS      1000
#define EVICT_ITERS     200   /* Fewer for eviction tests (MVU tree walk is slow) */
#define NUM_ADDRS        8

/* ---- Trap handler ---- */
static volatile int trap_count = 0;

void __attribute__((interrupt("machine"), aligned(4))) trap_handler(void)
{
    trap_count++;
    /* Skip the faulting instruction (4 bytes) */
    uint64_t mepc;
    asm volatile("csrr %0, mepc" : "=r"(mepc));
    mepc += 4;
    asm volatile("csrw mepc, %0" :: "r"(mepc));
}

/* ---- CSR helpers ---- */
static inline uint64_t read_mcycle(void)
{
    uint64_t v;
    asm volatile("csrr %0, mcycle" : "=r"(v));
    return v;
}

static inline void fence(void)
{
    asm volatile("fence rw,rw" ::: "memory");
}

/* Evict a line at `addr` by READING from a conflicting address.
 * For a direct-mapped cache, one read to the same set evicts the old line.
 * Using READS avoids the deadlock caused by store-based eviction:
 *   - Store to conflict addr → write-allocate cache miss → MVU intercepts read
 *   - But MVU is busy with UPDATE from the eviction it just caused → DEADLOCK
 * Reads to unprotected addresses are forwarded immediately by MVU (no UPDATE). */
static inline void evict_line(uintptr_t addr)
{
    uintptr_t set_offset = addr & 0xFFFUL;
    volatile uint64_t *c1 = (volatile uint64_t *)(UNPROT_BASE + set_offset);
    volatile uint64_t v = *c1;  /* Read evicts target from this set */
    (void)v;
    fence();
}

static void small_delay(void)
{
    /* Must be long enough for MVU to complete a full tree walk:
     * L1 read (8 beats) + L2 read (8 beats) + L3-L6 HCache lookups
     * + tree writes at L1, L2. ~5000 cycles should be safe. */
    for (volatile int d = 0; d < 5000; d++)
        asm volatile("nop");
}

/* ---- Warm-up: seed the hash tree ---- */
/* Write to every protected address we'll benchmark, evict it (so the MVU
 * UPDATE path runs and stores hashes in HCache), then wait.
 * After warm-up, every subsequent access to these lines will find valid
 * hashes in HCache and verification should pass. */
static void warmup_protected(void)
{
    printf("[WARMUP] Seeding hash tree for protected addresses...\n");
    /* Stride 0x200 = 8 leaves * 8 bytes * 8 arity = 512 bytes.
     * Each address maps to a DIFFERENT L1 sibling group so UPDATEs
     * don't interfere with each other's parent hashes in HCache. */
    for (int i = 0; i < NUM_ADDRS; i++) {
        volatile uint64_t *p = (volatile uint64_t *)(PROT_BASE + 0x2000UL + i * 0x200UL);
        *p = 0;
        fence();
        /* Evict inline (no function call = no stack access during MVU window) */
        uintptr_t set_off = (uintptr_t)p & 0xFFFUL;
        volatile uint64_t *c = (volatile uint64_t *)(UNPROT_BASE + set_off);
        volatile uint64_t cv = *c; (void)cv;
        fence();
        for (int d = 0; d < 10000; d++) asm volatile("nop");
    }
    /* Bench C address: far away in its own group */
    {
        volatile uint64_t *p = (volatile uint64_t *)(PROT_BASE + 0x5000UL);
        *p = 0;
        fence();
        uintptr_t set_off = (uintptr_t)p & 0xFFFUL;
        volatile uint64_t *c = (volatile uint64_t *)(UNPROT_BASE + set_off);
        volatile uint64_t cv = *c; (void)cv;
        fence();
        for (int d = 0; d < 10000; d++) asm volatile("nop");
    }

    /* Now read each address back to verify the tree was seeded (should NOT trap) */
    trap_count = 0;
    for (int i = 0; i < NUM_ADDRS; i++) {
        volatile uint64_t *q = (volatile uint64_t *)(PROT_BASE + 0x2000UL + i * 0x200UL);
        uintptr_t set_off = (uintptr_t)q & 0xFFFUL;
        volatile uint64_t *c = (volatile uint64_t *)(UNPROT_BASE + set_off);
        volatile uint64_t cv = *c; (void)cv;
        fence();
        for (int d = 0; d < 10000; d++) asm volatile("nop");
        volatile uint64_t v = *q;
        (void)v;
    }
    {
        volatile uint64_t *q = (volatile uint64_t *)(PROT_BASE + 0x5000UL);
        uintptr_t set_off = (uintptr_t)q & 0xFFFUL;
        volatile uint64_t *c = (volatile uint64_t *)(UNPROT_BASE + set_off);
        volatile uint64_t cv = *c; (void)cv;
        fence();
        for (int d = 0; d < 10000; d++) asm volatile("nop");
        volatile uint64_t v = *q;
        (void)v;
    }

    if (trap_count > 0)
        printf("[WARMUP] WARNING: %d traps during warm-up (HCache may have stale data)\n", trap_count);
    else
        printf("[WARMUP] Done. No traps (hash tree seeded correctly).\n");
}

/* ---- Benchmarks ---- */


/* A: Unprotected R/W baseline */
static uint64_t bench_unprotected_rw(void)
{
    volatile uint64_t *addrs[NUM_ADDRS];
    for (int i = 0; i < NUM_ADDRS; i++)
        addrs[i] = (volatile uint64_t *)(UNPROT_BASE + 0x2000UL + i * 0x40UL);

    fence();
    uint64_t start = read_mcycle();

    for (int iter = 0; iter < NUM_ITERS; iter++) {
        for (int i = 0; i < NUM_ADDRS; i++)
            *addrs[i] = (uint64_t)(iter + i);
        fence();
        volatile uint64_t sink = 0;
        for (int i = 0; i < NUM_ADDRS; i++)
            sink += *addrs[i];
        (void)sink;
    }

    fence();
    uint64_t end = read_mcycle();
    return end - start;
}

/* B: Protected R/W cache-hot */
static uint64_t bench_protected_rw_hot(void)
{
    volatile uint64_t *addrs[NUM_ADDRS];
    /* Stride 0x200: each address in a different L1 sibling group */
    for (int i = 0; i < NUM_ADDRS; i++)
        addrs[i] = (volatile uint64_t *)(PROT_BASE + 0x2000UL + i * 0x200UL);

    fence();
    uint64_t start = read_mcycle();

    for (int iter = 0; iter < NUM_ITERS; iter++) {
        for (int i = 0; i < NUM_ADDRS; i++)
            *addrs[i] = (uint64_t)(iter + i);
        fence();
        volatile uint64_t sink = 0;
        for (int i = 0; i < NUM_ADDRS; i++)
            sink += *addrs[i];
        (void)sink;
    }

    fence();
    uint64_t end = read_mcycle();
    return end - start;
}

/* C: Protected evict + read (MVU tree walk each read)
 * Done as single-shot measurements because the MVU blocks ALL cache reads
 * while in UPDATE state, which can stall even stack accesses in a tight loop. */
static uint64_t bench_protected_evict_read(void)
{
    /* Use an isolated address in its own L1 group, away from Bench B */
    volatile uint64_t *addr = (volatile uint64_t *)(PROT_BASE + 0x5000UL);
    uint64_t total_read_cycles = 0;

    for (int iter = 0; iter < EVICT_ITERS; iter++) {
        /* Phase 1: Write and evict (triggers MVU UPDATE) */
        *addr = (uint64_t)iter;
        fence();

        /* Evict by reading from conflict address */
        uintptr_t set_offset = (uintptr_t)addr & 0xFFFUL;
        volatile uint64_t *conflict = (volatile uint64_t *)(UNPROT_BASE + set_offset);
        volatile uint64_t cv = *conflict;
        (void)cv;
        fence();

        /* Wait for MVU UPDATE to finish - use asm nops only,
         * no memory accesses that could stall on the MVU */
        for (int d = 0; d < 10000; d++)
            asm volatile("nop");

        /* Phase 2: Timed read (MVU should be IDLE now → VERIFY path) */
        uint64_t t0 = read_mcycle();
        volatile uint64_t val = *addr;
        fence();
        uint64_t t1 = read_mcycle();
        (void)val;

        total_read_cycles += (t1 - t0);
    }

    return total_read_cycles;
}

/* D: Unprotected evict + read (eviction baseline, no MVU) */
static uint64_t bench_unprotected_evict_read(void)
{
    volatile uint64_t *addr = (volatile uint64_t *)(UNPROT_BASE + 0x3000UL);
    uint64_t total_read_cycles = 0;

    for (int iter = 0; iter < EVICT_ITERS; iter++) {
        *addr = (uint64_t)iter;
        fence();

        /* Evict by reading from a different address in the same set */
        uintptr_t set_offset = (uintptr_t)addr & 0xFFFUL;
        volatile uint64_t *conflict = (volatile uint64_t *)(UNPROT_BASE + EVICT_STRIDE + set_offset);
        volatile uint64_t cv = *conflict;
        (void)cv;
        fence();

        /* NOP delay (register-only, no memory access) */
        for (int d = 0; d < 10000; d++)
            asm volatile("nop");

        /* Timed read */
        uint64_t t0 = read_mcycle();
        volatile uint64_t val = *addr;
        fence();
        uint64_t t1 = read_mcycle();
        (void)val;

        total_read_cycles += (t1 - t0);
    }

    return total_read_cycles;
}

/* ---- Main ---- */

int main(void)
{
    /* Install trap handler */
    uintptr_t tvec = (uintptr_t)trap_handler & ~(uintptr_t)3;
    asm volatile("csrw mtvec, %0" :: "r"(tvec));

    printf("\n================================================\n");
    printf("  MVU PERFORMANCE BENCHMARK\n");
    printf("  R/W tests: %d iters, Evict tests: %d iters\n", NUM_ITERS, EVICT_ITERS);
    printf("================================================\n\n");

    /* Warm up: seed the hash tree so benchmarks don't hit first-time stores */
    warmup_protected();
    printf("\n");

    /* Run benchmarks */
    trap_count = 0;

    printf("[BENCH A] Unprotected read/write (baseline)...\n");
    uint64_t cyc_a = bench_unprotected_rw();
    printf("  Cycles: %llu  (%llu per iter)\n",
           (unsigned long long)cyc_a, (unsigned long long)(cyc_a / NUM_ITERS));

    printf("[BENCH B] Protected read/write (cache-hot)...\n");
    uint64_t cyc_b = bench_protected_rw_hot();
    printf("  Cycles: %llu  (%llu per iter)\n",
           (unsigned long long)cyc_b, (unsigned long long)(cyc_b / NUM_ITERS));

    printf("[BENCH C] Protected evict+read (MVU verify each)...\n");
    int traps_before = trap_count;
    uint64_t cyc_c = bench_protected_evict_read();
    int traps_c = trap_count - traps_before;
    printf("  Cycles: %llu  (%llu per iter, %d traps)\n",
           (unsigned long long)cyc_c, (unsigned long long)(cyc_c / EVICT_ITERS), traps_c);

    printf("[BENCH D] Unprotected evict+read (eviction baseline)...\n");
    uint64_t cyc_d = bench_unprotected_evict_read();
    printf("  Cycles: %llu  (%llu per iter)\n",
           (unsigned long long)cyc_d, (unsigned long long)(cyc_d / EVICT_ITERS));

    printf("\n================================================\n");
    printf("  SUMMARY (cycles per iteration)\n");
    printf("================================================\n");
    printf("  A) Unprotected R/W (baseline):  %llu\n", (unsigned long long)(cyc_a / NUM_ITERS));
    printf("  B) Protected R/W (cache-hot):   %llu\n", (unsigned long long)(cyc_b / NUM_ITERS));
    printf("  C) Protected evict+read (MVU):  %llu\n", (unsigned long long)(cyc_c / EVICT_ITERS));
    printf("  D) Unprotected evict+read:      %llu\n", (unsigned long long)(cyc_d / EVICT_ITERS));

    uint64_t per_c = cyc_c / EVICT_ITERS;
    uint64_t per_d = cyc_d / EVICT_ITERS;
    if (per_c > per_d)
        printf("  MVU verify cost (C-D):          %llu cycles\n",
               (unsigned long long)(per_c - per_d));

    if (cyc_d > 0 && cyc_c > cyc_d) {
        uint64_t pct = ((cyc_c - cyc_d) * 100) / cyc_d;
        printf("  MVU overhead %%:                  %llu%%\n", (unsigned long long)pct);
    }

    printf("  Traps during benchmarks:        %d\n", trap_count);
    printf("================================================\n");

    while (1)
        asm volatile("wfi");
}
