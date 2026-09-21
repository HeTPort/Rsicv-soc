#include <stdint.h>

#include "tohost.h"
#include "uart.h"

#define P0_UART_MARKER_START 0x504F5752u
#define P0_UART_MARKER_END   0x454E4421u
#define P0_UART_BYTE_COUNT   14u
#define P0_UART_FAIL_MESSAGE 0xBAD75001u

static const char message[] = "Hello, UART!\r\n";

volatile uint32_t p0_uart_poll_marker;
volatile uint32_t p0_uart_poll_result;

int main(void)
{
    if (sizeof(message) != P0_UART_BYTE_COUNT + 1u ||
        message[0] != 'H' || message[P0_UART_BYTE_COUNT - 1u] != '\n') {
        tohost_fail(P0_UART_FAIL_MESSAGE);
    }

    __asm__ volatile ("" ::: "memory");
    p0_uart_poll_marker = P0_UART_MARKER_START;
    __asm__ volatile ("" ::: "memory");

    uart_write(message);
    uart_wait_idle();

    __asm__ volatile ("" ::: "memory");
    p0_uart_poll_marker = P0_UART_MARKER_END;
    __asm__ volatile ("" ::: "memory");

    p0_uart_poll_result = P0_UART_BYTE_COUNT;
    tohost_write(1u);
    for (;;) {
        __asm__ volatile ("nop");
    }
}
