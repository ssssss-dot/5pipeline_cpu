# RV32I 裸机入口。必须放在 IRAM 的地址 0，不能直接从 C main 开始执行。
.option norvc
.option norelax
.section .text.start, "ax", @progbits
.globl _start
.type _start, @function
_start:
    # SP=0x80008000，16 字节对齐；栈向低地址增长。
    la sp, __stack_top
    la gp, __global_pointer$

    # 下载器直接将 .data（包括字符串）写入 DRAM，无需从 IRAM 复制数据。
    # .bss 不包含在下载镜像中，每次启动都由 CPU 清零。
    la t0, __bss_start
    la t1, __bss_end
.Lclear_bss:
    bgeu t0, t1, .Lrun_main
    sw zero, 0(t0)
    addi t0, t0, 4
    j .Lclear_bss
.Lrun_main:
    call main
.Lhalt:
    j .Lhalt
.size _start, .-_start
