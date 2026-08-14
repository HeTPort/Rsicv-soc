#include <stddef.h>
#include <stdint.h>

#include "gpio.h"
#include "timer.h"
#include "tohost.h"

static const uint32_t led_values[] = {0x01u, 0x02u, 0x04u, 0x08u, 0xA5u};

int main(void)
{
    for (size_t index = 0; index < sizeof(led_values) / sizeof(led_values[0]);
         ++index) {
        const uint64_t deadline = timer_read_mtime() + 20u;
        while (timer_read_mtime() < deadline) {
        }
        gpio_write(led_values[index]);
        if (gpio_read() != led_values[index]) {
            tohost_fail(0xBAD00200u + (uint32_t)index);
        }
    }

    tohost_write(1u);
    for (;;) {
        __asm__ volatile ("nop");
    }
}
