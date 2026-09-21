#include <stdint.h>

#include "tohost.h"

#define P0_RAM_WORDS          256u
#define P0_RAM_PASSES         32u
#define P0_RAM_SEED           0x1A2B3C4Du
#define P0_RAM_SALT_STEP      0x9E3779B9u
#define P0_RAM_GOLDEN         0x58873A00u
#define P0_RAM_FINAL_SALT     0xC6EF3720u
#define P0_RAM_CANARY_LOW     0x13579BDFu
#define P0_RAM_CANARY_HIGH    0x2468ACE0u
#define P0_RAM_MARKER_START   0x504F5752u
#define P0_RAM_MARKER_END     0x454E4421u

#define P0_RAM_FAIL_INIT      0xBAD73001u
#define P0_RAM_FAIL_CHECKSUM  0xBAD73002u
#define P0_RAM_FAIL_DATA      0xBAD73003u
#define P0_RAM_FAIL_CANARY    0xBAD73004u

typedef struct {
    volatile uint32_t canary_low;
    volatile uint32_t source[P0_RAM_WORDS];
    volatile uint32_t destination[P0_RAM_WORDS];
    volatile uint32_t canary_high;
} p0_ram_workspace_t;

static p0_ram_workspace_t workspace;
volatile uint32_t p0_ram_stream_marker;
volatile uint32_t p0_ram_stream_checksum;
volatile uint32_t p0_ram_stream_bytes;

static void initialize_workspace(void)
{
    uint32_t state = P0_RAM_SEED;
    uint32_t index;

    workspace.canary_low = P0_RAM_CANARY_LOW;
    workspace.canary_high = P0_RAM_CANARY_HIGH;
    for (index = 0u; index < P0_RAM_WORDS; ++index) {
        state = state * 1664525u + 1013904223u;
        workspace.source[index] = state;
        workspace.destination[index] = 0u;
    }
}

__attribute__((noinline))
static uint32_t run_stream(void)
{
    uint32_t checksum = 0u;
    uint32_t salt = 0u;
    uint32_t pass;

    for (pass = 0u; pass < P0_RAM_PASSES; ++pass) {
        uint32_t index;
        salt += P0_RAM_SALT_STEP;
        for (index = 0u; index < P0_RAM_WORDS; ++index) {
            const uint32_t value = workspace.source[index];
            const uint32_t updated = value ^ salt ^ index;
            workspace.destination[index] = updated;
            checksum += updated;
        }
    }
    return checksum;
}

int main(void)
{
    uint32_t checksum;
    uint32_t index;

    initialize_workspace();
    if (workspace.canary_low != P0_RAM_CANARY_LOW ||
        workspace.canary_high != P0_RAM_CANARY_HIGH) {
        tohost_fail(P0_RAM_FAIL_INIT);
    }

    __asm__ volatile ("" ::: "memory");
    p0_ram_stream_marker = P0_RAM_MARKER_START;
    __asm__ volatile ("" ::: "memory");

    checksum = run_stream();

    __asm__ volatile ("" ::: "memory");
    p0_ram_stream_marker = P0_RAM_MARKER_END;
    __asm__ volatile ("" ::: "memory");

    p0_ram_stream_checksum = checksum;
    p0_ram_stream_bytes = P0_RAM_WORDS * P0_RAM_PASSES * 8u;
    if (checksum != P0_RAM_GOLDEN) {
        tohost_fail(P0_RAM_FAIL_CHECKSUM);
    }
    for (index = 0u; index < P0_RAM_WORDS; ++index) {
        if (workspace.destination[index] !=
            (workspace.source[index] ^ P0_RAM_FINAL_SALT ^ index)) {
            tohost_fail(P0_RAM_FAIL_DATA);
        }
    }
    if (workspace.canary_low != P0_RAM_CANARY_LOW ||
        workspace.canary_high != P0_RAM_CANARY_HIGH) {
        tohost_fail(P0_RAM_FAIL_CANARY);
    }

    tohost_write(1u);
    for (;;) {
        __asm__ volatile ("nop");
    }
}
