#include <stdint.h>

#include "tohost.h"

#define P0_MIX_WORD_COUNT       256u
#define P0_MIX_ITERATIONS       2048u
#define P0_MIX_SEED             0x6D5A56E9u
#define P0_MIX_MARKER_START     0x504F5752u
#define P0_MIX_MARKER_END       0x454E4421u
#define P0_MIX_CANARY_LOW       0x13579BDFu
#define P0_MIX_CANARY_HIGH      0x2468ACE0u
#define P0_MIX_GOLDEN_CHECKSUM  0x46FC5BC9u

#define P0_MIX_FAIL_CANARY_INIT 0xBAD71001u
#define P0_MIX_FAIL_CANARY_END  0xBAD71002u
#define P0_MIX_FAIL_CHECKSUM    0xBAD71003u

typedef struct {
    volatile uint32_t canary_low;
    volatile uint32_t words[P0_MIX_WORD_COUNT];
    volatile uint32_t canary_high;
} p0_mix_workspace_t;

volatile uint32_t p0_mix_marker;
volatile uint32_t p0_mix_result_checksum;
volatile uint32_t p0_mix_completed_iterations;

static p0_mix_workspace_t workspace;

static uint32_t rotate_left(uint32_t value, uint32_t shift)
{
    return (value << shift) | (value >> (32u - shift));
}

static uint32_t initialize_workspace(void)
{
    uint32_t state = P0_MIX_SEED;
    uint32_t index;

    workspace.canary_low = P0_MIX_CANARY_LOW;
    workspace.canary_high = P0_MIX_CANARY_HIGH;
    for (index = 0u; index < P0_MIX_WORD_COUNT; ++index) {
        state = state * 1664525u + 1013904223u;
        workspace.words[index] = state ^ (index * 0x9E3779B9u);
    }
    return state;
}

__attribute__((noinline))
static uint32_t run_mixed_kernel(uint32_t state)
{
    uint32_t checksum = 0xA5A5A5A5u ^ state;
    uint32_t iteration;

    for (iteration = 0u; iteration < P0_MIX_ITERATIONS; ++iteration) {
        const uint32_t index =
            (state ^ (iteration * 0x045D9F3Bu)) & (P0_MIX_WORD_COUNT - 1u);
        const uint32_t other = (index + 37u) & (P0_MIX_WORD_COUNT - 1u);
        const uint32_t value_a = workspace.words[index];
        const uint32_t value_b = workspace.words[other];
        const uint32_t shift = (iteration & 15u) + 1u;
        uint32_t mixed = value_a + rotate_left(value_b, shift);
        uint32_t divisor;
        uint32_t quotient;
        uint32_t remainder;
        uint32_t updated;

        mixed ^= state;
        if (((mixed ^ iteration) & 1u) != 0u) {
            mixed = mixed * 33u + (iteration ^ 0xA5A5A5A5u);
        } else {
            mixed = (mixed ^ 0x3C6EF372u) + iteration * 17u;
        }

        divisor = ((value_b >> 24) & 31u) + 1u;
        quotient = mixed / divisor;
        remainder = mixed % divisor;
        updated = rotate_left(
            mixed ^ quotient ^ (remainder << 16), (index & 15u) + 1u);

        workspace.words[index] = updated;
        state = (state * 1664525u + 1013904223u) ^ updated ^ iteration;
        checksum = rotate_left(checksum ^ updated, 5u) + state + index;
    }

    return checksum;
}

int main(void)
{
    const uint32_t initialized_state = initialize_workspace();
    uint32_t checksum;

    if (workspace.canary_low != P0_MIX_CANARY_LOW ||
        workspace.canary_high != P0_MIX_CANARY_HIGH) {
        tohost_fail(P0_MIX_FAIL_CANARY_INIT);
    }

    __asm__ volatile ("" ::: "memory");
    p0_mix_marker = P0_MIX_MARKER_START;
    __asm__ volatile ("" ::: "memory");

    checksum = run_mixed_kernel(initialized_state);

    __asm__ volatile ("" ::: "memory");
    p0_mix_marker = P0_MIX_MARKER_END;
    __asm__ volatile ("" ::: "memory");

    p0_mix_result_checksum = checksum;
    p0_mix_completed_iterations = P0_MIX_ITERATIONS;

    if (workspace.canary_low != P0_MIX_CANARY_LOW ||
        workspace.canary_high != P0_MIX_CANARY_HIGH) {
        tohost_fail(P0_MIX_FAIL_CANARY_END);
    }
    if (checksum != P0_MIX_GOLDEN_CHECKSUM) {
        tohost_fail(P0_MIX_FAIL_CHECKSUM);
    }

    tohost_write(1u);
    for (;;) {
        __asm__ volatile ("nop");
    }
}
