#include <stdint.h>
#include <stdio.h>

/* ============================================================
 * Memory Map (matches hcache.bsv / tree_memory.bsv / Soc.defines)
 *   Protected data: 0x85000000 - 0x851FFFFF (2 MB)
 *   L1 tree nodes:  0x85200000 + index * 8
 *   L2 tree nodes:  0x85240000 + index * 8
 *   DRAM range:     0x80000000 - 0x8FFFFFFF
 *
 * Target address: 0x85000040 (protected)
 *   leaf index      = 0x40 / 8  = 8
 *   L1 parent index = 8  >> 3   = 1  (MVU computes this from leaves)
 *   L1 sibling      = index 0   (MVU reads this from tree memory)
 *   L1[0] phys addr = 0x85200000
 *
 * Cache: direct-mapped, 64 sets, 64B lines (dways=1, dsets=64)
 *   Set index = addr[11:6]
 * ============================================================ */

#define PROTECTED_ADDR    ((volatile uint64_t *)0x85000040UL)
#define L1_SIBLING_ADDR   ((volatile uint64_t *)0x85200000UL)  /* L1[0] */

/* For forcing eviction by store-conflict in the same cache set:
 *   0x85000040 -> set = (0x40 >> 6) & 0x3F = 1
 *   Conflicting address: same set, different tag = 0x85000040 + 64*64 = 0x85001040
 *   (Or just stride by total cache size = 64 sets * 64 bytes = 4096 = 0x1000)
 */
#define CONFLICT_ADDR_A   ((volatile uint64_t *)0x85001040UL)  /* same set as PROTECTED */
#define CONFLICT_ADDR_B   ((volatile uint64_t *)0x85002040UL)  /* another conflict */

/* For tree region flush: 0x85200000 -> set = 0
 *   Conflict at 0x85201000 (same set, different tag) */
#define TREE_CONFLICT_A   ((volatile uint64_t *)0x85201000UL)
#define TREE_CONFLICT_B   ((volatile uint64_t *)0x85202000UL)

/* Force-evict a single cache line by writing to 2 conflicting addresses
 * (direct-mapped = 1 way, so writing 1 conflict is enough, but 2 is safer) */
static inline void force_evict_set(volatile uint64_t *conflict_a,
                                   volatile uint64_t *conflict_b)
{
    *conflict_a = 0;
    asm volatile("fence rw,rw");
    *conflict_b = 0;
    asm volatile("fence rw,rw");
}

static void busy_wait(void)
{
    for (volatile uint32_t i = 0; i < 2000000U; i++)
        asm volatile("nop");
}

/* Trap handler */
static volatile int trap_fired = 0;
static volatile uint64_t trap_mcause = 0;
static volatile uint64_t trap_mepc = 0;

void __attribute__((interrupt("machine"), aligned(4))) trap_handler(void)
{
    asm volatile("csrr %0, mcause" : "=r"(trap_mcause));
    asm volatile("csrr %0, mepc"   : "=r"(trap_mepc));
    trap_fired = 1;

    printf("[TRAP] mcause=%llu mepc=0x%llx\n",
           (unsigned long long)trap_mcause, (unsigned long long)trap_mepc);

    /* Skip the faulting instruction (assume 4-byte instruction) */
    uint64_t mepc;
    asm volatile("csrr %0, mepc" : "=r"(mepc));
    mepc += 4;
    asm volatile("csrw mepc, %0" :: "r"(mepc));
    /* mret will return to mepc+4, skipping the faulting load */
}

int main(void)
{
    /* Install trap handler */
    uintptr_t tvec = (uintptr_t)trap_handler & ~(uintptr_t)3;
    asm volatile("csrw mtvec, %0" :: "r"(tvec));

    printf("\n========================================\n");
    printf("   MVU DIAGNOSTIC TEST SUITE\n");
    printf("========================================\n\n");

    /* ================================================================
     * DIAGNOSTIC A: Basic protected-region read/write
     * ================================================================ */
    printf("[DIAG A] Writing 0xAAAABBBBCCCCDDDD to 0x85000040...\n");
    *PROTECTED_ADDR = 0xAAAABBBBCCCCDDDDUL;
    asm volatile("fence rw,rw");
    uint64_t readback = *PROTECTED_ADDR;
    printf("[DIAG A] Read back: 0x%llx\n", (unsigned long long)readback);
    if (readback == 0xAAAABBBBCCCCDDDDUL)
        printf("[DIAG A] PASS: Protected region is accessible.\n\n");
    else
        printf("[DIAG A] FAIL: Got unexpected value.\n\n");

    /* ================================================================
     * DIAGNOSTIC B: Cache eviction via store-conflict
     *   Write value X, evict by writing to conflicting addresses,
     *   read back. If X returns, the evict + reload path works.
     * ================================================================ */
    printf("[DIAG B] Writing 0x1122334455667788 to 0x85000040...\n");
    *PROTECTED_ADDR = 0x1122334455667788UL;
    asm volatile("fence rw,rw");

    printf("[DIAG B] Forcing eviction via store-conflict at 0x%llx, 0x%llx...\n",
           (unsigned long long)(uintptr_t)CONFLICT_ADDR_A,
           (unsigned long long)(uintptr_t)CONFLICT_ADDR_B);
    force_evict_set(CONFLICT_ADDR_A, CONFLICT_ADDR_B);
    busy_wait();  /* Let any hardware pipelines settle */

    readback = *PROTECTED_ADDR;  /* Should be a cache miss → reload from DRAM */
    printf("[DIAG B] Read back after eviction: 0x%llx\n", (unsigned long long)readback);
    if (readback == 0x1122334455667788UL)
        printf("[DIAG B] PASS: Eviction + reload works for protected region.\n\n");
    else
        printf("[DIAG B] FAIL: Got unexpected value (eviction may not have worked).\n\n");

    /* ================================================================
     * DIAGNOSTIC C: Tree region read/write + eviction
     *   Write a known value to tree memory (L1[0]), flush, read back.
     *   Proves the tree region is SW-accessible and flushing works.
     * ================================================================ */
    printf("[DIAG C] Writing 0xFEEDFACEDEADC0DE to tree L1[0] at 0x85200000...\n");
    *L1_SIBLING_ADDR = 0xFEEDFACEDEADC0DEUL;
    asm volatile("fence rw,rw");

    printf("[DIAG C] Forcing eviction of tree line...\n");
    force_evict_set(TREE_CONFLICT_A, TREE_CONFLICT_B);
    busy_wait();

    readback = *L1_SIBLING_ADDR;
    printf("[DIAG C] Read back tree L1[0]: 0x%llx\n", (unsigned long long)readback);
    if (readback == 0xFEEDFACEDEADC0DEUL)
        printf("[DIAG C] PASS: Tree region accessible & flush works.\n\n");
    else
        printf("[DIAG C] FAIL: Got unexpected value.\n\n");

    /* ================================================================
     * DIAGNOSTIC D: Confirm no trap on clean MVU path
     *   Write to protected region, evict (triggers MVU update),
     *   wait, read back (triggers MVU verify). Since tree is untampered,
     *   this should NOT trap. If it DOES, MVU has a bug.
     * ================================================================ */
    printf("[DIAG D] Clean MVU round-trip (no corruption)...\n");
    printf("[DIAG D] Writing 0xDEADBEEFCAFEBABE to 0x85000040...\n");
    trap_fired = 0;
    *PROTECTED_ADDR = 0xDEADBEEFCAFEBABEUL;
    asm volatile("fence rw,rw");

    printf("[DIAG D] Evicting protected line (triggers MVU update)...\n");
    force_evict_set(CONFLICT_ADDR_A, CONFLICT_ADDR_B);
    busy_wait();

    printf("[DIAG D] Re-reading 0x85000040 (triggers MVU verify)...\n");
    readback = *PROTECTED_ADDR;
    printf("[DIAG D] Read back: 0x%llx, trap_fired=%d\n",
           (unsigned long long)readback, trap_fired);
    if (!trap_fired && readback == 0xDEADBEEFCAFEBABEUL)
        printf("[DIAG D] PASS: Clean MVU round-trip succeeded (no false positive).\n\n");
    else if (trap_fired)
        printf("[DIAG D] FAIL: Trap fired on clean data -- MVU has a false positive!\n\n");
    else
        printf("[DIAG D] FAIL: Wrong data returned.\n\n");

    /* ================================================================
     * DIAGNOSTIC E: Corrupt tree + read (the real test)
     *   Write to protected region, evict (MVU seeds tree),
     *   corrupt L1[0], evict the tree line,
     *   re-read protected addr. Should trap.
     * ================================================================ */
    printf("[DIAG E] Full misverification test...\n");

    /* E.1: Write and evict protected line to seed the hash tree */
    printf("[DIAG E] Writing 0xCAFECAFECAFECAFE to 0x85000040...\n");
    trap_fired = 0;
    *PROTECTED_ADDR = 0xCAFECAFECAFECAFEUL;
    asm volatile("fence rw,rw");

    printf("[DIAG E] Evicting protected line (MVU update path)...\n");
    force_evict_set(CONFLICT_ADDR_A, CONFLICT_ADDR_B);
    busy_wait();
    busy_wait();  /* Extra wait for MVU tree walk to complete */

    /* E.2: Read back tree L1[0] to see what the MVU (or default) stored */
    /* First evict any cached tree data */
    force_evict_set(TREE_CONFLICT_A, TREE_CONFLICT_B);
    busy_wait();
    uint64_t tree_before = *L1_SIBLING_ADDR;
    printf("[DIAG E] Tree L1[0] before corruption: 0x%llx\n",
           (unsigned long long)tree_before);

    /* E.3: Corrupt L1[0] */
    printf("[DIAG E] Corrupting L1[0] to 0xDEADDEADDEADDEAD...\n");
    *L1_SIBLING_ADDR = 0xDEADDEADDEADDEADUL;
    asm volatile("fence rw,rw");

    /* E.4: Evict the corrupted tree line to DRAM */
    printf("[DIAG E] Evicting tree line to DRAM...\n");
    force_evict_set(TREE_CONFLICT_A, TREE_CONFLICT_B);
    busy_wait();

    /* E.5: Verify corruption stuck */
    uint64_t tree_after = *L1_SIBLING_ADDR;
    printf("[DIAG E] Tree L1[0] after corruption: 0x%llx\n",
           (unsigned long long)tree_after);

    /* E.6: Evict the protected line AGAIN (it was reloaded when we
     * read it implicitly via DIAG D; make sure it's not cached) */
    force_evict_set(CONFLICT_ADDR_A, CONFLICT_ADDR_B);
    /* Also evict the tree line again so MVU reads fresh from DRAM */
    force_evict_set(TREE_CONFLICT_A, TREE_CONFLICT_B);
    busy_wait();

    /* E.7: The critical read -- should trigger MVU verification failure */
    printf("[DIAG E] Re-reading 0x85000040 -- expecting MVU fault...\n");
    readback = *PROTECTED_ADDR;
    printf("[DIAG E] Read returned: 0x%llx, trap_fired=%d\n",
           (unsigned long long)readback, trap_fired);

    if (trap_fired && (trap_mcause == 5 || trap_mcause == 7))
        printf("[DIAG E] PASS: MVU correctly detected misverification!\n\n");
    else if (trap_fired)
        printf("[DIAG E] PARTIAL: Trap fired but unexpected mcause=%llu\n\n",
               (unsigned long long)trap_mcause);
    else
        printf("[DIAG E] FAIL: No trap. MVU did not detect the corruption.\n\n");

    /* ================================================================ */
    printf("========================================\n");
    printf("   DIAGNOSTIC SUITE COMPLETE\n");
    printf("========================================\n");

    while (1)
        asm volatile("wfi");
}
