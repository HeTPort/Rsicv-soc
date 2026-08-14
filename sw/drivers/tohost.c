#include "tohost.h"

#include "mmio.h"
#include "soc_memory_map.h"

void tohost_write(uint32_t value)
{
    mmio_write32(SOC_TOHOST_ADDR, value);
}

void tohost_fail(uint32_t value)
{
    tohost_write(value);
    for (;;) {
        __asm__ volatile ("nop");
    }
}
