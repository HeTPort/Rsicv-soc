#include "timer.h"

#include "mmio.h"
#include "soc_memory_map.h"

uint64_t timer_read_mtime(void)
{
    uint32_t high_before;
    uint32_t low;
    uint32_t high_after;

    do {
        high_before = mmio_read32(SOC_MTIME_ADDR + 4u);
        low = mmio_read32(SOC_MTIME_ADDR);
        high_after = mmio_read32(SOC_MTIME_ADDR + 4u);
    } while (high_before != high_after);

    return ((uint64_t)high_after << 32) | low;
}

void timer_write_mtimecmp(uint64_t value)
{
    /* Prevent a transient early interrupt while updating the RV32 halves. */
    mmio_write32(SOC_MTIMECMP_ADDR, UINT32_MAX);
    mmio_write32(SOC_MTIMECMP_ADDR + 4u, (uint32_t)(value >> 32));
    mmio_write32(SOC_MTIMECMP_ADDR, (uint32_t)value);
}
