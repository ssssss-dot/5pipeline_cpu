OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    IRAM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
    DRAM (rw)  : ORIGIN = 0x80000000, LENGTH = 32K
}

SECTIONS
{
    .text ORIGIN(IRAM) :
    {
        KEEP(*(.text.start))
        *(.text .text.*)
        . = ALIGN(4);
    } > IRAM

    /* CPU 的 load/store 通道访问 DRAM，因此只读字符串也放在这里。
       合并成一个 .data 输出段，方便 objcopy 提取单独的数据镜像。 */
    .data ORIGIN(DRAM) :
    {
        *(.rodata .rodata.* .srodata .srodata.*)
        *(.data .data.* .sdata .sdata.*)
        . = ALIGN(4);
    } > DRAM

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.* .sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > DRAM

    PROVIDE(__global_pointer$ = ORIGIN(DRAM) + 0x800);
    __stack_top = ORIGIN(DRAM) + LENGTH(DRAM);
    __stack_limit = __stack_top - 4K;

    /DISCARD/ : { *(.eh_frame .eh_frame.* .comment .note .note.*) }

    ASSERT(_start == ORIGIN(IRAM), "CPU entry must be at address 0")
    ASSERT(SIZEOF(.text) <= LENGTH(IRAM), "IRAM exceeds 32 KiB")
    ASSERT(__bss_end <= __stack_limit, "DRAM data/BSS overlaps reserved 4 KiB stack")
}
