/*
 * RV32I 裸机测试：打印开始信息，设置两路 LED，检查读回并打印结果。
 * 无操作系统、无 libc；由 platform/start.S 设置栈、清 BSS 后调用 main。
 * 代码进入 IRAM；字符串、变量和栈进入 DRAM，布局由 platform/link.ld 定义。
 */
#include <stdint.h>

#ifndef LED_ACTIVE_LOW
#define LED_ACTIVE_LOW 0
#endif
#if LED_ACTIVE_LOW != 0 && LED_ACTIVE_LOW != 1
#error "LED_ACTIVE_LOW must be 0 or 1"
#endif

#define UART_TX_REG (*(volatile uint8_t *)0x40000000u)
#define LED_REG     (*(volatile uint32_t *)0x40001000u)

/* volatile 确保实际访问 DRAM/MMIO，不被编译器当作普通常量优化掉。 */
static volatile uint32_t led_on_value = LED_ACTIVE_LOW ? 0u : 3u;
static volatile uint32_t led_readback;

static void uart_putc(char ch)
{
    /* 对应字节写 sb。CPU 硬件会等待 UART ready，无需软件轮询。 */
    UART_TX_REG = (uint8_t)ch;
}

static void uart_puts(const char *text)
{
    while (*text != '\0') {
        uart_putc(*text++);
    }
}

static void uart_put_hex32(uint32_t value)
{
    static const char digits[] = "0123456789ABCDEF";
    /* 只使用移位和与操作，不依赖乘除法扩展或运行库。 */
    for (int shift = 28; shift >= 0; shift -= 4) {
        uart_putc(digits[(value >> shift) & 0xFu]);
    }
}

int main(void)
{
    uart_puts("LED test start\r\n");

    const uint32_t expected = led_on_value;
    LED_REG = expected;
    led_readback = LED_REG;

    if (led_readback != expected) {
        uart_puts("ERROR: LED register readback mismatch\r\n");
        uart_puts("expected=0x");
        uart_put_hex32(expected);
        uart_puts(", actual=0x");
        uart_put_hex32(led_readback);
        uart_puts("\r\n");
        return 1;
    }

    uart_puts("RV32I bare-metal C test\r\nLED_REG=0x");
    uart_put_hex32(led_readback);
    uart_puts(", readback OK\r\nUART OK\r\n");

    /* main 返回后，启动代码原地循环，LED 保持最后的设置。 */
    return 0;
}
