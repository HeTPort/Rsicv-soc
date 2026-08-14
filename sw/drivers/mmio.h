#ifndef SW_DRIVERS_MMIO_H
#define SW_DRIVERS_MMIO_H

#include <stdint.h>

static inline uint32_t mmio_read32(uint32_t address)
{
    return *(volatile const uint32_t *)(uintptr_t)address;
}

static inline void mmio_write32(uint32_t address, uint32_t value)
{
    *(volatile uint32_t *)(uintptr_t)address = value;
}

#endif
