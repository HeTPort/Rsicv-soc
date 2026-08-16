#ifndef SW_COMMON_LIBC_STRING_H
#define SW_COMMON_LIBC_STRING_H

#include <stddef.h>

void *memcpy(void *destination, const void *source, size_t count);
void *memset(void *destination, int value, size_t count);
int memcmp(const void *left, const void *right, size_t count);
size_t strlen(const char *text);
char *strcpy(char *destination, const char *source);

#endif
