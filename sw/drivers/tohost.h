#ifndef SW_DRIVERS_TOHOST_H
#define SW_DRIVERS_TOHOST_H

#include <stdint.h>

void tohost_write(uint32_t value);
void tohost_fail(uint32_t value) __attribute__((noreturn));

#endif
