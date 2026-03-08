#include <stdint.h>
#include <stdio.h>

#define PROTECTED_ADDR    ((volatile uint64_t *)0x85000040UL)
#define L1_SIBLING_ADDR   ((volatile uint64_t *)0x85200000UL)
#define CONFLICT_ADDR_A   ((volatile uint64_t *)0x84000040UL)
#define TREE_CONFLICT_A   ((volatile uint64_t *)0x85201000UL)

static inline void force_evict(volatile uint64_t *conflict) {
    volatile uint64_t v = *conflict;
    (void)v;
    asm volatile("fence rw,rw");
}

static inline void sync_memory() {
    asm volatile("fence rw,rw");
}

static void busy_wait(void) {
    for (volatile uint32_t i = 0; i < 2000000U; i++) asm volatile("nop");
}

static volatile int trap_fired = 0;
static volatile uint64_t trap_cause = 0;

void __attribute__((interrupt("machine"), aligned(4))) trap_handler(void) {
    trap_fired = 1;

    uint64_t mcause;
    asm volatile("csrr %0, mcause" : "=r"(mcause));
    trap_cause = mcause;

    uint64_t mepc;
    asm volatile("csrr %0, mepc" : "=r"(mepc));
    mepc += 4; // Skip the faulting instruction
    asm volatile("csrw mepc, %0" :: "r"(mepc));
}

int main(void) {
    uintptr_t tvec = (uintptr_t)trap_handler & ~(uintptr_t)3;
    asm volatile("csrw mtvec, %0" :: "r"(tvec));

    printf("\n=== MVU TREE MEMORY WRITEBACK TEST ===\n\n");

    printf("1. Checking initial state of Tree Memory L1[0] (0x85200000)...\n");
    force_evict(TREE_CONFLICT_A); // ensure not cached
    uint64_t tree_init = *L1_SIBLING_ADDR;
    printf("   Initial L1[0] = 0x%016llx\n\n", (unsigned long long)tree_init);

    printf("2. Writing to protected region 0x85000040 (makes cache line dirty)...\n");
    *PROTECTED_ADDR = 0xDEADBEEFCAFEBABEUL;
    asm volatile("fence rw,rw");

    printf("3. Forcing eviction of protected cache line (should trigger MVU UPDATE)...\n");
    force_evict(CONFLICT_ADDR_A);
    busy_wait(); // Wait for MVU tree walk

    printf("4. Checking Tree Memory L1[0] after eviction...\n");
    force_evict(TREE_CONFLICT_A); // flush cached tree nodes
    busy_wait();
    uint64_t tree_after = *L1_SIBLING_ADDR;
    printf("   After eviction L1[0] = 0x%016llx\n\n", (unsigned long long)tree_after);

    if (tree_init != tree_after) {
        printf("PASS: Tree memory was updated by the MVU!\n");
    } else {
        printf("FAIL: Tree memory did not change. MVU writes are dropping!\n");
        printf("========================================\n");
    }

    printf("\n=== MVU MISVERIFICATION EXCEPTION TEST ===\n\n");
    
    printf("5. Corrupting Tree Memory L1[0]...\n");
    *L1_SIBLING_ADDR = 0xBADBADBADBADBADBULL;
    sync_memory();
    // Flush the corrupting write so the MVU sees it when checking
    force_evict(TREE_CONFLICT_A); 
    busy_wait();

    // Flush the protected region again so reading it requires a fresh verify
    printf("6. Flushing protected region from cache...\n");
    force_evict(CONFLICT_ADDR_A);
    busy_wait();

    printf("7. Reading protected region 0x85000040 (Should trigger verify fault)...\n");
    trap_fired = 0;
    trap_cause = 0;
    volatile uint64_t read_val = *PROTECTED_ADDR;
    (void)read_val; // Use it so compiler doesnt optimize away
    sync_memory();

    if (trap_fired) {
        printf("PASS: Caught Exception!\n");
        if (trap_cause == 5) { // 5 = Load Access Fault (common for security/perms)
            printf("      Cause: Load Access Fault (mcause=5) - MVU Verification Failed!\n");
        } else {
            printf("      Cause: mcause=%llu\n", (unsigned long long)trap_cause);
        }
    } else {
        printf("FAIL: No exception fired. MVU did not block the corrupt read.\n");
    }

    printf("========================================\n");
    asm volatile("li a0, 0x0");
    asm volatile("li a7, 0x5d"); // ecall to end program in Shakti SDK
    asm volatile("ecall");
    while(1) asm volatile("wfi");
}
