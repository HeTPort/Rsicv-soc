"""Independent fixed-width oracle for the P0 sequential RAM-stream workload."""

WORDS = 256
PASSES = 32
SEED = 0x1A2B3C4D
MASK = 0xFFFFFFFF


def run() -> tuple[int, int]:
    state = SEED
    source = []
    for _ in range(WORDS):
        state = (state * 1664525 + 1013904223) & MASK
        source.append(state)

    checksum = 0
    salt = 0
    destination = [0] * WORDS
    for _ in range(PASSES):
        salt = (salt + 0x9E3779B9) & MASK
        for index, value in enumerate(source):
            updated = value ^ salt ^ index
            destination[index] = updated
            checksum = (checksum + updated) & MASK

    for index, value in enumerate(destination):
        assert value == (source[index] ^ salt ^ index)
    return checksum, salt


if __name__ == "__main__":
    checksum, final_salt = run()
    print(f"checksum=0x{checksum:08X} final_salt=0x{final_salt:08X}")
