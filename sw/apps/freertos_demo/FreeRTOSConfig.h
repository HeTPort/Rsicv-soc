#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#include <stdint.h>

#include "soc_memory_map.h"

void freertos_assert_failed(const char *file, uint32_t line)
    __attribute__((noreturn));
void freertos_task_returned(void) __attribute__((noreturn));

/* The FPGA SoC clock and mtime clock are identical when TICK_CYCLES is one. */
#ifndef configCPU_CLOCK_HZ
#define configCPU_CLOCK_HZ                 25000000UL
#endif
#define configTICK_RATE_HZ                 1000U
#define configMTIME_BASE_ADDRESS           SOC_MTIME_ADDR
#define configMTIMECMP_BASE_ADDRESS        SOC_MTIMECMP_ADDR

#define configUSE_PREEMPTION               1
#define configUSE_TIME_SLICING             1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 0
#define configNUMBER_OF_CORES              1
#define configMAX_PRIORITIES               4
#define configMINIMAL_STACK_SIZE           128U
#define configMAX_TASK_NAME_LEN            12
#define configTICK_TYPE_WIDTH_IN_BITS      TICK_TYPE_WIDTH_32_BITS
#define configIDLE_SHOULD_YIELD            1

#define configSUPPORT_STATIC_ALLOCATION    0
#define configSUPPORT_DYNAMIC_ALLOCATION   1
#define configTOTAL_HEAP_SIZE              (24U * 1024U)
#define configAPPLICATION_ALLOCATED_HEAP   0
#define configHEAP_CLEAR_MEMORY_ON_FREE    0

#define configUSE_IDLE_HOOK                0
#define configUSE_TICK_HOOK                1
#define configUSE_MALLOC_FAILED_HOOK       1
#define configCHECK_FOR_STACK_OVERFLOW     2
#define configUSE_TIMERS                   0
#define configUSE_MUTEXES                  0
#define configUSE_RECURSIVE_MUTEXES        0
#define configUSE_COUNTING_SEMAPHORES      0
#define configUSE_QUEUE_SETS               0
#define configQUEUE_REGISTRY_SIZE          0
#define configUSE_CO_ROUTINES              0
#define configUSE_TRACE_FACILITY           0
#define configUSE_STATS_FORMATTING_FUNCTIONS 0
#define configUSE_NEWLIB_REENTRANT         0
#define configENABLE_FPU                   0
#define configENABLE_VPU                   0

#define INCLUDE_vTaskDelay                1
#define INCLUDE_vTaskDelayUntil           1
#define INCLUDE_vTaskSuspend              0
#define INCLUDE_vTaskDelete               0
#define INCLUDE_uxTaskPriorityGet         0
#define INCLUDE_vTaskPrioritySet          0

#define configTASK_RETURN_ADDRESS          freertos_task_returned
#define configASSERT(condition) \
    do { \
        if (!(condition)) { \
            freertos_assert_failed(__FILE__, (uint32_t)__LINE__); \
        } \
    } while (0)

#endif
