#ifndef SW_COMMON_RUNTIME_H
#define SW_COMMON_RUNTIME_H

#include <stdint.h>

extern unsigned char __stack_bottom[];
extern unsigned char __stack_top[];
extern unsigned char runtime_global_pointer[] __asm__("__global_pointer$");
extern void trap_entry(void);

static inline uintptr_t runtime_read_sp(void)
{
    uintptr_t value;
    __asm__ volatile ("mv %0, sp" : "=r"(value));
    return value;
}

static inline uintptr_t runtime_read_gp(void)
{
    uintptr_t value;
    __asm__ volatile ("mv %0, gp" : "=r"(value));
    return value;
}

#endif
