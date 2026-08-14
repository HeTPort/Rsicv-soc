#include <stdint.h>

#include "csr.h"
#include "gpio.h"
#include "timer.h"
#include "tohost.h"

#define MCAUSE_MACHINE_TIMER 0x80000007u
#define REQUIRED_TICKS       10u
#define TICK_DELTA           1000u

static volatile uint32_t timer_irq_count;

void timer_irq_handler(void)
{
    const uint32_t cause = csr_read_mcause();
    if (cause != MCAUSE_MACHINE_TIMER || csr_read_mtval() != 0u) {
        tohost_fail(0xBAD00301u);
    }

    /* Move the level-sensitive source inactive before returning with mret. */
    timer_write_mtimecmp(timer_read_mtime() + TICK_DELTA);
    ++timer_irq_count;
    gpio_write(timer_irq_count);
}

int main(void)
{
    timer_write_mtimecmp(timer_read_mtime() + TICK_DELTA);
    csr_write_mie(MIE_MTIE);
    csr_set_mstatus(MSTATUS_MIE);

    while (timer_irq_count < REQUIRED_TICKS) {
        __asm__ volatile ("wfi");
    }

    csr_clear_mstatus(MSTATUS_MIE);
    csr_write_mie(0u);
    timer_write_mtimecmp(UINT64_MAX);

    if (timer_irq_count != REQUIRED_TICKS || gpio_read() != REQUIRED_TICKS) {
        tohost_fail(0xBAD00302u);
    }

    tohost_write(1u);
    for (;;) {
        __asm__ volatile ("nop");
    }
}
