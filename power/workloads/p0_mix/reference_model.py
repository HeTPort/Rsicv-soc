#!/usr/bin/env python3
"""Independent unsigned-32-bit reference model for the p0_mix kernel."""

from __future__ import annotations


WORD_COUNT = 256
ITERATIONS = 2048
SEED = 0x6D5A56E9
MASK32 = 0xFFFFFFFF
GOLDEN_CHECKSUM = 0x46FC5BC9


def u32(value: int) -> int:
    return value & MASK32


def rotate_left(value: int, shift: int) -> int:
    value = u32(value)
    return u32((value << shift) | (value >> (32 - shift)))


def calculate() -> tuple[int, list[int]]:
    state = SEED
    words: list[int] = []
    for index in range(WORD_COUNT):
        state = u32(state * 1664525 + 1013904223)
        words.append(u32(state ^ u32(index * 0x9E3779B9)))

    checksum = u32(0xA5A5A5A5 ^ state)
    for iteration in range(ITERATIONS):
        index = u32(state ^ u32(iteration * 0x045D9F3B)) & (WORD_COUNT - 1)
        other = (index + 37) & (WORD_COUNT - 1)
        value_a = words[index]
        value_b = words[other]
        shift = (iteration & 15) + 1
        mixed = u32(value_a + rotate_left(value_b, shift))
        mixed = u32(mixed ^ state)
        if ((mixed ^ iteration) & 1) != 0:
            mixed = u32(mixed * 33 + u32(iteration ^ 0xA5A5A5A5))
        else:
            mixed = u32((mixed ^ 0x3C6EF372) + iteration * 17)

        divisor = ((value_b >> 24) & 31) + 1
        quotient = mixed // divisor
        remainder = mixed % divisor
        updated = rotate_left(
            mixed ^ quotient ^ u32(remainder << 16), (index & 15) + 1
        )

        words[index] = updated
        state = u32(u32(state * 1664525 + 1013904223) ^ updated ^ iteration)
        checksum = u32(rotate_left(checksum ^ updated, 5) + state + index)

    return checksum, words


def main() -> int:
    checksum, words = calculate()
    print(f"P0_MIX_WORD_COUNT={WORD_COUNT}")
    print(f"P0_MIX_ITERATIONS={ITERATIONS}")
    print(f"P0_MIX_SEED=0x{SEED:08X}")
    print(f"P0_MIX_GOLDEN_CHECKSUM=0x{checksum:08X}")
    print(f"P0_MIX_FINAL_WORD_XOR=0x{xor_words(words):08X}")
    if checksum != GOLDEN_CHECKSUM:
        print(f"ERROR: expected 0x{GOLDEN_CHECKSUM:08X}")
        return 1
    return 0


def xor_words(words: list[int]) -> int:
    result = 0
    for word in words:
        result = u32(result ^ word)
    return result


if __name__ == "__main__":
    raise SystemExit(main())
