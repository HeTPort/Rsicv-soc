#include "gpio.h"

#include "mmio.h"
#include "soc_memory_map.h"

void gpio_write(uint32_t value)
{
    mmio_write32(SOC_GPIO_OUT_ADDR, value);
}

uint32_t gpio_read(void)
{
    return mmio_read32(SOC_GPIO_OUT_ADDR);
}
