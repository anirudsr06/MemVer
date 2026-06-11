/*
 * MVU Performance Benchmark
 */

#include <stdint.h>
#include <stdio.h>

/* ---- Addresses ---- */
#define PROT_BASE     0x85000000UL
#define UNPROT_BASE   0x84000000UL

#define NUM_ITERS     1000
#define EVICT_ITERS   200
#define NUM_ADDRS     8

#define LARGE_SIZE    (256 * 1024)

/* ---- Trap handler ---- */
static volatile int trap_count = 0;

void __attribute__((interrupt("machine"), aligned(4))) trap_handler(void)
{
    trap_count++;
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

/* ---- Strong eviction ---- */
static inline void evict_line(uintptr_t addr)
{
    uintptr_t set_offset = addr & 0xFFFUL;

    for (int i = 0; i < 8; i++) {
        volatile uint64_t *c =
            (volatile uint64_t *)(UNPROT_BASE + set_offset + i * 0x1000);
        volatile uint64_t v = *c;
        (void)v;
    }

    fence();
}

/* ---- Warmup (no delay) ---- */
static void warmup_protected(void)
{
    for (int i = 0; i < 16; i++) {
        volatile uint64_t *p = (volatile uint64_t *)(PROT_BASE + i * 0x200);
        *p = i;
        fence();
        evict_line((uintptr_t)p);
        /* NO DELAY */
    }
}

/* ================= ORIGINAL TESTS ================= */

/* A */
static uint64_t bench_unprotected_rw(void)
{
    volatile uint64_t *addr = (volatile uint64_t *)UNPROT_BASE;

    uint64_t start = read_mcycle();

    for (int i = 0; i < NUM_ITERS; i++) {
        *addr = i;
        volatile uint64_t v = *addr;
        (void)v;
    }

    return read_mcycle() - start;
}

/* B */
static uint64_t bench_protected_rw(void)
{
    volatile uint64_t *addr = (volatile uint64_t *)PROT_BASE;

    uint64_t start = read_mcycle();

    for (int i = 0; i < NUM_ITERS; i++) {
        *addr = i;
        volatile uint64_t v = *addr;
        (void)v;
    }

    return read_mcycle() - start;
}

/* C (no delay → measures overlapped behavior) */
static uint64_t bench_protected_evict_read(void)
{
    volatile uint64_t *addr = (volatile uint64_t *)(PROT_BASE + 0x5000);
    uint64_t total = 0;

    for (int i = 0; i < EVICT_ITERS; i++) {
        *addr = i;
        fence();

        evict_line((uintptr_t)addr);

        /* NO DELAY HERE */

        uint64_t t0 = read_mcycle();
        volatile uint64_t v = *addr;
        fence();
        uint64_t t1 = read_mcycle();

        total += (t1 - t0);
        (void)v;
    }

    return total;
}

/* D */
static uint64_t bench_unprotected_evict_read(void)
{
    volatile uint64_t *addr = (volatile uint64_t *)(UNPROT_BASE + 0x3000);
    uint64_t total = 0;

    for (int i = 0; i < EVICT_ITERS; i++) {
        *addr = i;
        fence();

        evict_line((uintptr_t)addr);

        /* NO DELAY */

        uint64_t t0 = read_mcycle();
        volatile uint64_t v = *addr;
        fence();
        uint64_t t1 = read_mcycle();

        total += (t1 - t0);
        (void)v;
    }

    return total;
}

/* ================= EXTENDED TESTS ================= */

static uint64_t bench_stream(uintptr_t base)
{
    volatile uint64_t *arr = (volatile uint64_t *)base;
    uint32_t n = LARGE_SIZE / sizeof(uint64_t);

    uint64_t start = read_mcycle();

    for (uint32_t i = 0; i < n; i++) {
        evict_line((uintptr_t)&arr[i]);
        /* NO DELAY */
        volatile uint64_t v = arr[i];
        (void)v;
    }

    return read_mcycle() - start;
}

static uint32_t seed = 1;
static uint32_t fast_rand(void)
{
    seed = seed * 1103515245 + 12345;
    return seed;
}

static uint64_t bench_random(uintptr_t base)
{
    volatile uint64_t *arr = (volatile uint64_t *)base;
    uint32_t n = LARGE_SIZE / sizeof(uint64_t);

    uint64_t start = read_mcycle();

    for (uint32_t i = 0; i < n; i++) {
        uint32_t idx = fast_rand() % n;
        evict_line((uintptr_t)&arr[idx]);
        /* NO DELAY */
        volatile uint64_t v = arr[idx];
        (void)v;
    }

    return read_mcycle() - start;
}

static uint64_t bench_write(uintptr_t base)
{
    volatile uint64_t *arr = (volatile uint64_t *)base;
    uint32_t n = LARGE_SIZE / sizeof(uint64_t);

    uint64_t start = read_mcycle();

    for (uint32_t i = 0; i < n; i++) {
        arr[i] = i;
        fence();
        evict_line((uintptr_t)&arr[i]);
        /* NO DELAY */
    }

    return read_mcycle() - start;
}

/* ================= MAIN ================= */

int main(void)
{
    uintptr_t tvec = (uintptr_t)trap_handler & ~(uintptr_t)3;
    asm volatile("csrw mtvec, %0" :: "r"(tvec));

    printf("\n==== MVU BENCH ====\n");

    warmup_protected();

    uint64_t a = bench_unprotected_rw();
    uint64_t b = bench_protected_rw();
    uint64_t c = bench_protected_evict_read();
    uint64_t d = bench_unprotected_evict_read();

    printf("\n[A] Unprot RW: %llu\n", a);
    printf("[B] Prot RW:   %llu\n", b);
    printf("[C] Prot Read: %llu\n", c / EVICT_ITERS);
    printf("[D] Unprot Read:%llu\n", d / EVICT_ITERS);

    printf("MVU Cost (C-D): %llu cycles\n",
           (c/EVICT_ITERS) - (d/EVICT_ITERS));

    printf("\n[STREAM]\n");
    printf("  Unprot: %llu\n", bench_stream(UNPROT_BASE));
    printf("  Prot:   %llu\n", bench_stream(PROT_BASE));

    printf("\n[RANDOM]\n");
    printf("  Unprot: %llu\n", bench_random(UNPROT_BASE));
    printf("  Prot:   %llu\n", bench_random(PROT_BASE));

    printf("\n[WRITE]\n");
    printf("  Unprot: %llu\n", bench_write(UNPROT_BASE));
    printf("  Prot:   %llu\n", bench_write(PROT_BASE));

    printf("\nDONE\n");

    while (1) asm volatile("wfi");
}
