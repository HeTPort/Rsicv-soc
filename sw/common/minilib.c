#include <stddef.h>

void *memcpy(void *destination, const void *source, size_t count)
{
    unsigned char *dst = (unsigned char *)destination;
    const unsigned char *src = (const unsigned char *)source;

    while (count != 0u) {
        *dst++ = *src++;
        --count;
    }
    return destination;
}

void *memset(void *destination, int value, size_t count)
{
    unsigned char *dst = (unsigned char *)destination;

    while (count != 0u) {
        *dst++ = (unsigned char)value;
        --count;
    }
    return destination;
}

int memcmp(const void *left, const void *right, size_t count)
{
    const unsigned char *lhs = (const unsigned char *)left;
    const unsigned char *rhs = (const unsigned char *)right;

    while (count != 0u) {
        if (*lhs != *rhs) {
            return (int)*lhs - (int)*rhs;
        }
        ++lhs;
        ++rhs;
        --count;
    }
    return 0;
}

size_t strlen(const char *text)
{
    const char *cursor = text;
    while (*cursor != '\0') {
        ++cursor;
    }
    return (size_t)(cursor - text);
}

char *strcpy(char *destination, const char *source)
{
    char *dst = destination;
    do {
        *dst++ = *source;
    } while (*source++ != '\0');
    return destination;
}
