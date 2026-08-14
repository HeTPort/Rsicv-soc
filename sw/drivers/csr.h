#ifndef SW_DRIVERS_CSR_H
#define SW_DRIVERS_CSR_H

#include <stdint.h>

#define MSTATUS_MIE (1u << 3)
#define MIE_MTIE    (1u << 7)

static inline uint32_t csr_read_mstatus(void)
{
    uint32_t value;
    __asm__ volatile ("csrr %0, mstatus" : "=r"(value));
    return value;
}

static inline uint32_t csr_read_mtvec(void)
{
    uint32_t value;
    __asm__ volatile ("csrr %0, mtvec" : "=r"(value));
    return value;
}

static inline uint32_t csr_read_mcause(void)
{
    uint32_t value;
    __asm__ volatile ("csrr %0, mcause" : "=r"(value));
    return value;
}

static inline uint32_t csr_read_mtval(void)
{
    uint32_t value;
    __asm__ volatile ("csrr %0, mtval" : "=r"(value));
    return value;
}

static inline void csr_set_mstatus(uint32_t mask)
{
    __asm__ volatile ("csrs mstatus, %0" :: "r"(mask) : "memory");
}

static inline void csr_clear_mstatus(uint32_t mask)
{
    __asm__ volatile ("csrc mstatus, %0" :: "r"(mask) : "memory");
}

static inline void csr_write_mie(uint32_t value)
{
    __asm__ volatile ("csrw mie, %0" :: "r"(value) : "memory");
}

#endif
