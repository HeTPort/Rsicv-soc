#ifndef SW_DRIVERS_TIMER_H
#define SW_DRIVERS_TIMER_H

#include <stdint.h>

uint64_t timer_read_mtime(void);
void timer_write_mtimecmp(uint64_t value);

#endif
