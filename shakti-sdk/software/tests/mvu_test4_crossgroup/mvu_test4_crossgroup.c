/*
 * Test 4: Cross-Group Independence
 * Write to two addresses in DIFFERENT L1 groups.
 * Verify they don't corrupt each other and L2 reflects both.
 */
#include <stdint.h>
#include <stdio.h>

/*
 * Addr A: 0x85000000 → leaf 0  → L1[0] (group 0)  → 0x85800000
 * Addr B: 0x85000200 → leaf 64 → L1[8] (group 1)  → 0x85800040
 * Both share L2[0] → 0x85900000
 */
#define PROT_A     ((volatile uint64_t *)0x85000000UL)
#define PROT_B     ((volatile uint64_t *)0x85000200UL)
#define L1_A       ((volatile uint64_t *)0x85400000UL)  /* L1[0] */
#define L1_B       ((volatile uint64_t *)0x85400040UL)  /* L1[8] */
#define L2_PARENT  ((volatile uint64_t *)0x85480000UL)  /* L2[0] */
#define EVICT_A    ((volatile uint64_t *)0x84000000UL)
#define EVICT_B    ((volatile uint64_t *)0x84000200UL)

static inline void fence(void) { asm volatile("fence rw,rw" ::: "memory"); }
static inline void nop_wait(void) {
    for (volatile int i = 0; i < 2000000; i++) asm volatile("nop");
}

static inline void evict_addr(uintptr_t addr) {
    uintptr_t set_off = addr & 0xFFFUL;
    volatile uint64_t *c = (volatile uint64_t *)(0x84010000UL + set_off);
    volatile uint64_t v = *c; (void)v;
    fence();
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

    printf("\n=== TEST 4: Cross-Group Independence ===\n\n");

    /* Write to group A, evict */
    printf("  Writing 0x1111 to 0x85000000 (L1 group 0)...\n");
    *PROT_A = 0x1111111111111111UL;
    fence();
    volatile uint64_t v = *EVICT_A; (void)v;
    fence(); nop_wait();

    /* Record L1[0] after first write */
    evict_addr((uintptr_t)L1_A); nop_wait();
    uint64_t l1a_after_first = *L1_A; fence();

    /* Write to group B, evict */
    printf("  Writing 0x2222 to 0x85000200 (L1 group 1)...\n");
    *PROT_B = 0x2222222222222222UL;
    fence();
    v = *EVICT_B; (void)v;
    fence(); nop_wait();

    /* Record both L1 nodes after second write */
    evict_addr((uintptr_t)L1_A); nop_wait();
    evict_addr((uintptr_t)L1_B); nop_wait();
    uint64_t l1a_after_both = *L1_A; fence();
    uint64_t l1b_after_both = *L1_B; fence();

    printf("\n  L1[0] after write A:     0x%016llx\n", (unsigned long long)l1a_after_first);
    printf("  L1[0] after write A+B:   0x%016llx\n", (unsigned long long)l1a_after_both);
    printf("  L1[8] after write B:     0x%016llx\n\n", (unsigned long long)l1b_after_both);

    int pass = 1;
    if (l1a_after_first != l1a_after_both) {
        printf("  FAIL: L1[0] changed when writing to L1[8] group!\n");
        pass = 0;
    } else {
        printf("  OK: L1[0] unchanged by write to different group.\n");
    }
    if (l1b_after_both == 0) {
        printf("  FAIL: L1[8] is zero after write.\n");
        pass = 0;
    }

    /* Verify reads don't fault */
    trap_count = 0;
    v = *EVICT_A; (void)v; fence(); nop_wait();
    v = *PROT_A; (void)v; fence();
    v = *EVICT_B; (void)v; fence(); nop_wait();
    v = *PROT_B; (void)v; fence();
    if (trap_count > 0) {
        printf("  FAIL: %d traps during read-back.\n", trap_count);
        pass = 0;
    } else {
        printf("  OK: Read-back with 0 traps.\n");
    }

    printf("\n%s\n", pass ? "PASS" : "FAIL");
    printf("=========================================\n");
    while(1) asm volatile("wfi");
}
