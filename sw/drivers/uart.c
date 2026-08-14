#include "uart.h"

#include "mmio.h"
#include "soc_memory_map.h"

void uart_putc(uint8_t value)
{
    while ((mmio_read32(SOC_UART_STATUS_ADDR) & UART_STATUS_TX_READY) == 0u) {
    }
    mmio_write32(SOC_UART_TXDATA_ADDR, value);
}

void uart_write(const char *text)
{
    while (*text != '\0') {
        uart_putc((uint8_t)*text);
        ++text;
    }
}

void uart_wait_idle(void)
{
    while ((mmio_read32(SOC_UART_STATUS_ADDR) & UART_STATUS_TX_BUSY) != 0u) {
    }
}
