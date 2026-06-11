/*
 * Test 6: Boundary Address Test
 * Verify correct behavior at the edges of the protected region.
 */
#include <stdint.h>
#include <stdio.h>

#define PROT_FIRST    ((volatile uint64_t *)0x85000000UL)
#define PROT_LAST     ((volatile uint64_t *)0x853FFFC0UL)
#define OUTSIDE_ABOVE ((volatile uint64_t *)0x85400000UL)
#define OUTSIDE_BELOW ((volatile uint64_t *)0x84FFFFC0UL)

static inline void fence(void) { asm volatile("fence rw,rw" ::: "memory"); }
static inline void nop_wait(void) {
    for (volatile int i = 0; i < 2000000; i++) asm volatile("nop");
}

static volatile int trap_count = 0;
void __attribute__((interrupt("machine"), aligned(4))) trap_handler(void) {
    trap_count++;
    uint64_t mepc;
    asm volatile("csrr %0, mepc" : "=r"(mepc));
    mepc += 4;
    asm volatile("csrw mepc, %0" :: "r"(mepc));
}

static inline void evict_addr(uintptr_t addr) {
    uintptr_t set_off = addr & 0xFFFUL;
    volatile uint64_t *c = (volatile uint64_t *)(0x84010000UL + set_off);
    volatile uint64_t v = *c; (void)v;
    fence();
}

int main(void) {
    uintptr_t tvec = (uintptr_t)trap_handler & ~(uintptr_t)3;
    asm volatile("csrw mtvec, %0" :: "r"(tvec));

    printf("\n=== TEST 6: Boundary Address Test ===\n\n");
    int pass = 1;

    /* First protected address */
    printf("  [1] First (0x85000000)...\n");
    *PROT_FIRST = 0xAAAAAAAAAAAAAAAAUL;
    fence();
    evict_addr((uintptr_t)PROT_FIRST); nop_wait();
    evict_addr((uintptr_t)PROT_FIRST); nop_wait();
    trap_count = 0;
    volatile uint64_t v = *PROT_FIRST; (void)v; fence();
    printf("    traps: %d %s\n", trap_count, trap_count==0?"OK":"FAIL");
    if (trap_count) pass = 0;

    /* Last protected cache line */
    printf("  [2] Last (0x853FFFC0)...\n");
    *PROT_LAST = 0xBBBBBBBBBBBBBBBBUL;
    fence();
    evict_addr((uintptr_t)PROT_LAST); nop_wait();
    evict_addr((uintptr_t)PROT_LAST); nop_wait();
    trap_count = 0;
    v = *PROT_LAST; (void)v; fence();
    printf("    traps: %d %s\n", trap_count, trap_count==0?"OK":"FAIL");
    if (trap_count) pass = 0;

    /* Above protected (tree region) */
    printf("  [3] Above (0x85400000, tree)...\n");
    trap_count = 0;
    v = *OUTSIDE_ABOVE; (void)v; fence();
    printf("    traps: %d %s\n", trap_count, trap_count==0?"OK":"FAIL");
    if (trap_count) pass = 0;

    /* Below protected */
    printf("  [4] Below (0x84FFFFC0)...\n");
    trap_count = 0;
    v = *OUTSIDE_BELOW; (void)v; fence();
    printf("    traps: %d %s\n", trap_count, trap_count==0?"OK":"FAIL");
    if (trap_count) pass = 0;

    printf("\n%s\n", pass ? "PASS" : "FAIL");
    printf("======================================\n");
    while(1) asm volatile("wfi");
}
