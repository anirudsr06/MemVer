/* Minimal linker script for Shakti on Arty A7 */
/* Boot ROM loads at 0x1000, jumps to DRAM at 0x80000000 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    /* Main DRAM - place code above the protected data region */
    DRAM (rwx) : ORIGIN = 0x80200000, LENGTH = 2M
}

SECTIONS
{
    .text : {
        *(.text._start)
        *(.text .text.*)
    } > DRAM

    .rodata : {
        *(.rodata .rodata.*)
    } > DRAM

    .data : {
        *(.data .data.*)
    } > DRAM

    .bss : {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > DRAM

    /* Stack at end of DRAM */
    . = ORIGIN(DRAM) + LENGTH(DRAM) - 8;
    __stack_top = .;
}
