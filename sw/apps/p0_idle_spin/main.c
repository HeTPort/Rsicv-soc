#include <stdint.h>

#include "tohost.h"

#define P0_IDLE_ITERATIONS   65536u
#define P0_MARKER_START      0x504F5752u
#define P0_MARKER_END        0x454E4421u
#define P0_IDLE_FAIL_COUNT  0xBAD74001u

volatile uint32_t p0_idle_spin_marker;
volatile uint32_t p0_idle_spin_result;

int main(void)
{
    uint32_t remaining = P0_IDLE_ITERATIONS;

    __asm__ volatile ("" ::: "memory");
    p0_idle_spin_marker = P0_MARKER_START;
    __asm__ volatile ("" ::: "memory");

    /* A clocked, memory-quiet reference; this is intentionally not WFI. */
    __asm__ volatile (
        "1:\n\t"
        "nop\n\t"
        "addi %0, %0, -1\n\t"
        "bnez %0, 1b\n\t"
        : "+r" (remaining)
        :
        : "memory");

    __asm__ volatile ("" ::: "memory");
    p0_idle_spin_marker = P0_MARKER_END;
    __asm__ volatile ("" ::: "memory");

    p0_idle_spin_result = remaining;
    if (remaining != 0u) {
        tohost_fail(P0_IDLE_FAIL_COUNT);
    }
    tohost_write(1u);
    for (;;) {
        __asm__ volatile ("nop");
    }
}
