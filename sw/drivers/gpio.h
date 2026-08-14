#ifndef SW_DRIVERS_GPIO_H
#define SW_DRIVERS_GPIO_H

#include <stdint.h>

void gpio_write(uint32_t value);
uint32_t gpio_read(void);

#endif
