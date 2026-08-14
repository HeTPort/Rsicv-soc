#include <stdint.h>

#include "csr.h"
#include "runtime.h"
#include "tohost.h"
#include "uart.h"

static volatile uint32_t bss_probe __attribute__((section(".bss.startup_probe")));
static volatile uint32_t data_probe = 0x12345678u;
static const char message[] = "Hello, UART!\r\n";

int main(void)
{
    const uintptr_t sp = runtime_read_sp();
    const uintptr_t gp = runtime_read_gp();
    const uintptr_t stack_bottom = (uintptr_t)__stack_bottom;
    const uintptr_t stack_top = (uintptr_t)__stack_top;

    if (bss_probe != 0u) {
        tohost_fail(0xBAD00101u);
    }
    if (data_probe != 0x12345678u) {
        tohost_fail(0xBAD00102u);
    }
    if (message[0] != 'H' || message[sizeof(message) - 2u] != '\n') {
        tohost_fail(0xBAD00103u);
    }
    if ((sp & 0xFu) != 0u || sp <= stack_bottom || sp > stack_top) {
        tohost_fail(0xBAD00104u);
    }
    if (gp != (uintptr_t)runtime_global_pointer) {
        tohost_fail(0xBAD00105u);
    }
    if (csr_read_mtvec() != (uintptr_t)trap_entry) {
        tohost_fail(0xBAD00106u);
    }

    uart_write(message);
    uart_wait_idle();
    tohost_write(1u);
    for (;;) {
        __asm__ volatile ("nop");
    }
}
