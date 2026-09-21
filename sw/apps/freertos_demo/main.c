#include <stdint.h>

#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"

#include "gpio.h"
#include "tohost.h"
#include "uart.h"

#ifndef SOC_FREERTOS_DEMO_TIME_SCALE
#define SOC_FREERTOS_DEMO_TIME_SCALE 1U
#endif

#ifndef SOC_FREERTOS_SIM_COMPLETION
#define SOC_FREERTOS_SIM_COMPLETION 0U
#endif

#ifndef SOC_FREERTOS_MIN_QUEUE_RECEIVES
#define SOC_FREERTOS_MIN_QUEUE_RECEIVES 8U
#endif

#ifndef SOC_FREERTOS_MIN_LED_UPDATES
#define SOC_FREERTOS_MIN_LED_UPDATES 2U
#endif

#ifndef SOC_FREERTOS_MIN_HEARTBEATS
#define SOC_FREERTOS_MIN_HEARTBEATS 1U
#endif

#ifndef SOC_FREERTOS_MIN_TICK_HOOKS
#define SOC_FREERTOS_MIN_TICK_HOOKS 0U
#endif

#ifndef SOC_FREERTOS_POWER_PROFILE
#define SOC_FREERTOS_POWER_PROFILE 0U
#endif

#define P0_FREERTOS_WARMUP_RECEIVES 12U
#define P0_FREERTOS_WINDOW_RECEIVES 16U
#define P0_FREERTOS_END_RECEIVES \
    (P0_FREERTOS_WARMUP_RECEIVES + P0_FREERTOS_WINDOW_RECEIVES)
#define P0_FREERTOS_MARKER_START 0x504F5752u
#define P0_FREERTOS_MARKER_END   0x454E4421u
#define P0_FREERTOS_FAIL_COUNTS 0xBAD64001u

#define DEMO_STACK_WORDS 192U
#define DEMO_QUEUE_DEPTH 4U
#define DEMO_FAIL_BASE   0xBAD60000u

static QueueHandle_t demo_queue;
static volatile uint32_t tick_hook_count;
static volatile uint32_t led_update_count;
static volatile uint32_t heartbeat_count;
static volatile uint32_t queue_receive_count;

#if SOC_FREERTOS_POWER_PROFILE
volatile uint32_t p0_freertos_marker;
volatile uint32_t p0_freertos_window_ticks;
volatile uint32_t p0_freertos_window_led_updates;
volatile uint32_t p0_freertos_window_heartbeats;
static uint32_t p0_start_ticks;
static uint32_t p0_start_led_updates;
static uint32_t p0_start_heartbeats;
#endif

BaseType_t context_sentinel_queue_send(QueueHandle_t queue, const void *item);

static TickType_t demo_delay_ticks(uint32_t milliseconds)
{
    TickType_t ticks = pdMS_TO_TICKS(milliseconds / SOC_FREERTOS_DEMO_TIME_SCALE);
    return (ticks == 0U) ? 1U : ticks;
}

static uint32_t demo_required_tick_hooks(void)
{
    if (SOC_FREERTOS_MIN_TICK_HOOKS != 0U) {
        return SOC_FREERTOS_MIN_TICK_HOOKS;
    }
    return (uint32_t)demo_delay_ticks(1000U);
}

static void led_task(void *argument)
{
    uint32_t led_value = 1U;
    (void)argument;

    for (;;) {
        gpio_write(led_value);
        ++led_update_count;
        led_value ^= 1U;
        vTaskDelay(demo_delay_ticks(500U));
    }
}

static void heartbeat_task(void *argument)
{
    (void)argument;
    uart_write("FreeRTOS RV32IM\r\n");
    uart_wait_idle();

    for (;;) {
        vTaskDelay(demo_delay_ticks(1000U));
        uart_write("heartbeat\r\n");
        uart_wait_idle();
        ++heartbeat_count;
    }
}

static void queue_producer_task(void *argument)
{
    uint32_t value = 1U;
    (void)argument;

    for (;;) {
        vTaskDelay(demo_delay_ticks(100U));
        if (context_sentinel_queue_send(demo_queue, &value) != pdPASS) {
            tohost_fail(DEMO_FAIL_BASE | 0x11U);
        }
        ++value;
    }
}

static void queue_receiver_task(void *argument)
{
    uint32_t expected = 1U;
    uint32_t value;
    (void)argument;

    for (;;) {
        if (xQueueReceive(demo_queue, &value, portMAX_DELAY) != pdPASS) {
            tohost_fail(DEMO_FAIL_BASE | 0x21U);
        }
        if (value != expected) {
            tohost_fail(DEMO_FAIL_BASE | 0x22U);
        }
        ++expected;
        ++queue_receive_count;

#if SOC_FREERTOS_POWER_PROFILE
        if (queue_receive_count == P0_FREERTOS_WARMUP_RECEIVES) {
            p0_start_ticks = tick_hook_count;
            p0_start_led_updates = led_update_count;
            p0_start_heartbeats = heartbeat_count;
            __asm__ volatile ("" ::: "memory");
            p0_freertos_marker = P0_FREERTOS_MARKER_START;
            __asm__ volatile ("" ::: "memory");
        }
        if (queue_receive_count == P0_FREERTOS_END_RECEIVES) {
            __asm__ volatile ("" ::: "memory");
            p0_freertos_marker = P0_FREERTOS_MARKER_END;
            __asm__ volatile ("" ::: "memory");
            taskDISABLE_INTERRUPTS();
            p0_freertos_window_ticks = tick_hook_count - p0_start_ticks;
            p0_freertos_window_led_updates =
                led_update_count - p0_start_led_updates;
            p0_freertos_window_heartbeats =
                heartbeat_count - p0_start_heartbeats;
            if (queue_receive_count != P0_FREERTOS_END_RECEIVES ||
                p0_freertos_window_ticks < P0_FREERTOS_WINDOW_RECEIVES ||
                p0_freertos_window_led_updates < 2u ||
                p0_freertos_window_heartbeats < 1u) {
                tohost_fail(P0_FREERTOS_FAIL_COUNTS);
            }
            tohost_write(1u);
            for (;;) {
                __asm__ volatile ("nop");
            }
        }
#endif

        if (SOC_FREERTOS_SIM_COMPLETION != 0U &&
            queue_receive_count >= SOC_FREERTOS_MIN_QUEUE_RECEIVES &&
            led_update_count >= SOC_FREERTOS_MIN_LED_UPDATES &&
            heartbeat_count >= SOC_FREERTOS_MIN_HEARTBEATS &&
            tick_hook_count >= demo_required_tick_hooks()) {
            taskDISABLE_INTERRUPTS();
            tohost_write(1U);
            for (;;) {
                __asm__ volatile ("nop");
            }
        }
    }
}

void vApplicationTickHook(void)
{
    ++tick_hook_count;
}

void vApplicationMallocFailedHook(void)
{
    tohost_fail(DEMO_FAIL_BASE | 0x31U);
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *task_name)
{
    (void)task;
    (void)task_name;
    tohost_fail(DEMO_FAIL_BASE | 0x32U);
}

void freertos_assert_failed(const char *file, uint32_t line)
{
    (void)file;
    (void)line;
    tohost_fail(DEMO_FAIL_BASE | 0x33U);
}

void freertos_task_returned(void)
{
    tohost_fail(DEMO_FAIL_BASE | 0x34U);
}

void freertos_risc_v_application_exception_handler(void)
{
    tohost_fail(DEMO_FAIL_BASE | 0x35U);
}

void freertos_risc_v_application_interrupt_handler(void)
{
    tohost_fail(DEMO_FAIL_BASE | 0x36U);
}

int main(void)
{
    demo_queue = xQueueCreate(DEMO_QUEUE_DEPTH, sizeof(uint32_t));
    if (demo_queue == NULL) {
        tohost_fail(DEMO_FAIL_BASE | 0x01U);
    }

    if (xTaskCreate(queue_receiver_task, "queue-rx", DEMO_STACK_WORDS, NULL,
                    3U, NULL) != pdPASS ||
        xTaskCreate(heartbeat_task, "heartbeat", DEMO_STACK_WORDS, NULL,
                    2U, NULL) != pdPASS ||
        xTaskCreate(led_task, "led", DEMO_STACK_WORDS, NULL,
                    1U, NULL) != pdPASS ||
        xTaskCreate(queue_producer_task, "queue-tx", DEMO_STACK_WORDS, NULL,
                    1U, NULL) != pdPASS) {
        tohost_fail(DEMO_FAIL_BASE | 0x02U);
    }

    vTaskStartScheduler();
    tohost_fail(DEMO_FAIL_BASE | 0x03U);
}
