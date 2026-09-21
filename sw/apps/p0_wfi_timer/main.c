#include <stdint.h>

#include "csr.h"
#include "timer.h"
#include "tohost.h"

#define MCAUSE_MACHINE_TIMER       0x80000007u
#define P0_WFI_REQUIRED_WAKES      64u
#define P0_WFI_TICK_DELTA          4096u
#define P0_WFI_MARKER_START        0x504F5752u
#define P0_WFI_MARKER_END          0x454E4421u
#define P0_WFI_FAIL_TRAP           0xBAD72001u
#define P0_WFI_FAIL_WAKE_COUNT     0xBAD72002u

volatile uint32_t p0_wfi_timer_marker;
volatile uint32_t p0_wfi_timer_wake_count;

void timer_irq_handler(void)
{
    if (csr_read_mcause() != MCAUSE_MACHINE_TIMER || csr_read_mtval() != 0u) {
        tohost_fail(P0_WFI_FAIL_TRAP);
    }

    /* Deassert the level-sensitive source before MRET. */
    timer_write_mtimecmp(timer_read_mtime() + P0_WFI_TICK_DELTA);
    ++p0_wfi_timer_wake_count;
}

int main(void)
{
    p0_wfi_timer_wake_count = 0u;
    timer_write_mtimecmp(timer_read_mtime() + P0_WFI_TICK_DELTA);
    csr_write_mie(MIE_MTIE);
    csr_set_mstatus(MSTATUS_MIE);

    __asm__ volatile ("" ::: "memory");
    p0_wfi_timer_marker = P0_WFI_MARKER_START;
    __asm__ volatile ("" ::: "memory");

    while (p0_wfi_timer_wake_count < P0_WFI_REQUIRED_WAKES) {
        __asm__ volatile ("wfi");
    }

    csr_clear_mstatus(MSTATUS_MIE);
    csr_write_mie(0u);
    timer_write_mtimecmp(UINT64_MAX);

    __asm__ volatile ("" ::: "memory");
    p0_wfi_timer_marker = P0_WFI_MARKER_END;
    __asm__ volatile ("" ::: "memory");

    if (p0_wfi_timer_wake_count != P0_WFI_REQUIRED_WAKES) {
        tohost_fail(P0_WFI_FAIL_WAKE_COUNT);
    }

    tohost_write(1u);
    for (;;) {
        __asm__ volatile ("nop");
    }
}
