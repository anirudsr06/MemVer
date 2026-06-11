/*
 * Test 8: Multi-Address Stress
 * Write to N distinct protected addresses, evict all, read all back.
 * Zero traps expected.
 */
#include <stdint.h>
#include <stdio.h>

#define PROT_BASE   0x85000000UL
#define UNPROT_BASE 0x84000000UL
#define NUM_ADDRS   8
#define STRIDE      0x200UL  /* 512B apart — different L1 groups */

static inline void fence(void) { asm volatile("fence rw,rw" ::: "memory"); }
static inline void nop_wait(void) {
    for (volatile int i = 0; i < 2000000; i++) asm volatile("nop");
}

static inline void evict(uintptr_t addr) {
    uintptr_t set_off = addr & 0xFFFUL;
    volatile uint64_t *c = (volatile uint64_t *)(UNPROT_BASE + set_off);
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

    printf("\n=== TEST 8: Multi-Address Stress ===\n\n");
    printf("  Writing to %d addresses...\n", NUM_ADDRS);

    /* Write and evict each address */
    for (int i = 0; i < NUM_ADDRS; i++) {
        volatile uint64_t *addr = (volatile uint64_t *)(PROT_BASE + i * STRIDE);
        *addr = 0xA0A0A0A000000000UL + i;
        fence();
        evict((uintptr_t)addr);
        nop_wait();
    }

    /* Read back all */
    printf("  Reading back all %d addresses...\n", NUM_ADDRS);
    trap_count = 0;
    int pass = 1;
    for (int i = 0; i < NUM_ADDRS; i++) {
        volatile uint64_t *addr = (volatile uint64_t *)(PROT_BASE + i * STRIDE);
        evict((uintptr_t)addr);
        nop_wait();
        uint64_t val = *addr;
        fence();
        uint64_t expected = 0xA0A0A0A000000000UL + i;
        if (val != expected) {
            printf("    FAIL at 0x%lx: got 0x%016llx expected 0x%016llx\n",
                   (unsigned long)(PROT_BASE + i * STRIDE),
                   (unsigned long long)val, (unsigned long long)expected);
            pass = 0;
        }
    }

    printf("  Traps: %d\n\n", trap_count);
    if (trap_count > 0) pass = 0;
    printf("%s\n", pass ? "PASS: All addresses verified." : "FAIL");
    printf("=====================================\n");
    while(1) asm volatile("wfi");
}
