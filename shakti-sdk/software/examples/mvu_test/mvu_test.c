/*
 * MVU (Memory Verification Unit) Presence Test
 * ==============================================
 * 
 * This test confirms the MVU is present and active in the Shakti SoC.
 *
 * ARCHITECTURE NOTES:
 *   - MVU sits between dcache and memory, intercepting all reads
 *   - Protected region: 0x8000_0000 - 0x801F_FFFF (main DRAM)
 *   - Non-protected accesses pass through transparently
 *   - Protected accesses trigger Merkle tree verification
 *
 * CURRENT LIMITATION:
 *   The tree memory ports (for fetching sibling nodes) are not yet
 *   connected to the AXI4 fabric in ccore.bsv. This means:
 *   - Non-protected reads: work normally (MVU passthrough)
 *   - Protected reads: MVU tries to verify, but hangs waiting for
 *     tree node data that can never arrive
 *
 * TEST STRATEGY:
 *   We use the RDCYCLE CSR to measure how many cycles a memory read
 *   takes. The MVU adds observable cycle overhead even for non-protected
 *   reads (FIFO traversal), and protected reads will timeout/hang
 *   (confirming tree verification is attempting to run).
 *
 * BUILD:
 *   riscv64-unknown-elf-gcc -O0 -march=rv64imac -mabi=lp64 \
 *       -nostdlib -nostartfiles -T link.ld mvu_test.c -o mvu_test.elf
 *
 * RUN:
 *   Load via GDB over OpenOCD JTAG connection to the Arty board.
 */

#include <stdint.h>

// UART register addresses (from Soc.defines: UartBase = 0x0001_1300)
#define UART_BASE       0x00011300UL
#define UART_TX_REG     (*(volatile uint32_t *)(UART_BASE + 0x00)) // THR
#define UART_STATUS_REG (*(volatile uint32_t *)(UART_BASE + 0x0C)) // LSR
#define UART_TX_READY   (1 << 5)  // THR empty bit in LSR

// Protected region boundaries (from hcache.bsv)
#define PROTECTED_BASE  0x80000000UL
#define PROTECTED_END   0x801FFFFFUL

// Non-protected DRAM (above tree region)
#define NON_PROTECTED   0x80300000UL

// Read cycle counter
static inline uint64_t rdcycle(void) {
    uint64_t val;
    __asm__ volatile ("rdcycle %0" : "=r"(val));
    return val;
}

// Simple UART output
static void uart_putc(char c) {
    while (!(UART_STATUS_REG & UART_TX_READY));
    UART_TX_REG = c;
}

static void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

static void uart_put_hex64(uint64_t val) {
    const char hex[] = "0123456789abcdef";
    uart_puts("0x");
    for (int i = 60; i >= 0; i -= 4) {
        uart_putc(hex[(val >> i) & 0xF]);
    }
}

static void uart_put_dec(uint64_t val) {
    char buf[20];
    int i = 0;
    if (val == 0) { uart_putc('0'); return; }
    while (val > 0) {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    }
    while (--i >= 0) uart_putc(buf[i]);
}

// Measure read latency in cycles
static uint64_t measure_read_latency(volatile uint64_t *addr) {
    uint64_t start, end;
    volatile uint64_t val;
    
    // Ensure no outstanding memory operations
    __asm__ volatile ("fence" ::: "memory");
    
    start = rdcycle();
    val = *addr;  // The read we're measuring
    __asm__ volatile ("fence" ::: "memory");
    end = rdcycle();
    
    (void)val;
    return end - start;
}

void _start(void) {
    // Banner
    uart_puts("\r\n");
    uart_puts("=============================================\r\n");
    uart_puts("  Shakti SoC - MVU Presence Test\r\n");
    uart_puts("=============================================\r\n\r\n");

    // --------------------------------------------------------
    // Test 1: Non-protected read (should work, MVU passthrough)
    // --------------------------------------------------------
    uart_puts("[Test 1] Non-protected read at ");
    uart_put_hex64(NON_PROTECTED);
    uart_puts("\r\n");

    // Write a known pattern first
    volatile uint64_t *np_ptr = (volatile uint64_t *)NON_PROTECTED;
    *np_ptr = 0xCAFEBABE12345678ULL;
    __asm__ volatile ("fence" ::: "memory");

    // Read it back and measure
    uint64_t np_latency = measure_read_latency(np_ptr);
    uint64_t np_val = *np_ptr;

    uart_puts("  Value read: ");
    uart_put_hex64(np_val);
    uart_puts("\r\n");
    uart_puts("  Latency:    ");
    uart_put_dec(np_latency);
    uart_puts(" cycles\r\n");

    if (np_val == 0xCAFEBABE12345678ULL) {
        uart_puts("  RESULT:     PASS (non-protected read works)\r\n");
    } else {
        uart_puts("  RESULT:     FAIL (data mismatch!)\r\n");
    }
    uart_puts("\r\n");

    // --------------------------------------------------------
    // Test 2: Multiple non-protected reads to get avg latency
    // --------------------------------------------------------
    uart_puts("[Test 2] Non-protected read latency (10 samples)\r\n");
    uint64_t total = 0;
    for (int i = 0; i < 10; i++) {
        volatile uint64_t *addr = (volatile uint64_t *)(NON_PROTECTED + i * 64);
        *addr = (uint64_t)(i + 1);
        __asm__ volatile ("fence" ::: "memory");
        // Flush dcache line by reading other addresses to cause eviction
        for (int j = 0; j < 64; j++) {
            volatile uint64_t *flush = (volatile uint64_t *)(NON_PROTECTED + 0x10000 + j * 64);
            (void)*flush;
        }
        uint64_t lat = measure_read_latency(addr);
        uart_puts("  Read ");
        uart_put_dec(i);
        uart_puts(": ");
        uart_put_dec(lat);
        uart_puts(" cycles\r\n");
        total += lat;
    }
    uart_puts("  Average: ");
    uart_put_dec(total / 10);
    uart_puts(" cycles\r\n\r\n");

    // --------------------------------------------------------
    // Test 3: Protected region read (MVU verification attempt)
    // WARNING: This WILL HANG because tree memory ports are
    // not connected to AXI fabric. The hang itself confirms
    // the MVU is active and attempting verification.
    // --------------------------------------------------------
    uart_puts("[Test 3] Protected region read at ");
    uart_put_hex64(PROTECTED_BASE + 0x40);
    uart_puts("\r\n");
    uart_puts("  NOTE: If system hangs here, MVU is ACTIVE and\r\n");
    uart_puts("        attempting Merkle verification (expected).\r\n");
    uart_puts("  The tree memory ports need AXI4 connection to\r\n");
    uart_puts("  complete verification without hanging.\r\n");
    uart_puts("  Testing with timeout...\r\n");

    // Try the protected read with a cycle-count timeout
    volatile uint64_t *prot_ptr = (volatile uint64_t *)(PROTECTED_BASE + 0x40);
    
    // We cannot truly implement a software timeout for a blocking load.
    // If the load hangs, we'll never reach the timeout check.
    // So instead, we print the message BEFORE the load.
    uart_puts("  Attempting protected read NOW...\r\n");
    
    // This load will either:
    // (a) Complete quickly if MVU is NOT present (normal cache miss)
    // (b) HANG if MVU is present and tree memory is unconnected
    uint64_t prot_val = *prot_ptr;
    
    // If we reach here, MVU verification somehow completed
    // (either MVU was optimized out, or tree memory is actually connected)
    uart_puts("  Value: ");
    uart_put_hex64(prot_val);
    uart_puts("\r\n");
    uart_puts("  RESULT: Protected read completed (MVU may be inactive)\r\n\r\n");

    // --------------------------------------------------------
    // Summary
    // --------------------------------------------------------
    uart_puts("=============================================\r\n");
    uart_puts("  Test Complete\r\n");
    uart_puts("=============================================\r\n");
    uart_puts("If Test 3 hung: MVU IS PRESENT AND ACTIVE.\r\n");
    uart_puts("  -> Tree memory AXI4 connection needed.\r\n");
    uart_puts("If Test 3 passed: MVU may be optimized out\r\n");
    uart_puts("  or was disabled by BSC optimization.\r\n");
    uart_puts("\r\n");

    // Spin forever
    while (1);
}
