/*
 * Test 5: Repeated Update Consistency
 * Write different values to the same address, evict each time.
 * Tree should update consistently and reads should never fault.
 */
#include <stdint.h>
#include <stdio.h>

#define PROT_ADDR   ((volatile uint64_t *)0x85000040UL)
#define EVICT_PROT  ((volatile uint64_t *)0x84000040UL)
#define NUM_ROUNDS  5

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

int main(void) {
    uintptr_t tvec = (uintptr_t)trap_handler & ~(uintptr_t)3;
    asm volatile("csrw mtvec, %0" :: "r"(tvec));

    printf("\n=== TEST 5: Repeated Update Consistency ===\n\n");

    int pass = 1;
    for (int i = 0; i < NUM_ROUNDS; i++) {
        uint64_t val = 0x1000000000000000UL * (i + 1) + i;

        /* Write new value */
        *PROT_ADDR = val;
        fence();

        /* Evict → MVU update */
        volatile uint64_t v = *EVICT_PROT; (void)v;
        fence(); nop_wait();

        /* Read back → MVU verify */
        v = *EVICT_PROT; (void)v;
        fence(); nop_wait();

        trap_count = 0;
        uint64_t readback = *PROT_ADDR;
        fence();

        printf("  Round %d: wrote=0x%016llx read=0x%016llx traps=%d\n",
               i + 1, (unsigned long long)val,
               (unsigned long long)readback, trap_count);

        if (readback != val) {
            printf("    FAIL: Data mismatch!\n");
            pass = 0;
        }
        if (trap_count > 0) {
            printf("    FAIL: Unexpected trap!\n");
            pass = 0;
        }
    }

    printf("\n%s\n", pass ? "PASS: All rounds consistent." : "FAIL");
    printf("=============================================\n");
    while(1) asm volatile("wfi");
}
