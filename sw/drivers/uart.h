#ifndef SW_DRIVERS_UART_H
#define SW_DRIVERS_UART_H

#include <stdint.h>

#define UART_STATUS_TX_READY (1u << 0)
#define UART_STATUS_TX_BUSY  (1u << 1)
#define UART_STATUS_RX_VALID (1u << 2)

void uart_putc(uint8_t value);
void uart_write(const char *text);
void uart_wait_idle(void);

#endif
