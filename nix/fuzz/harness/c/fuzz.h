/* nix/fuzz/harness/c/fuzz.h
 *
 * Helpers for the libFuzzer harnesses.  Each harness #includes the .c file it
 * tests, so it reaches static functions without changing src/.
 */
#ifndef INFIX_FUZZ_H_
#define INFIX_FUZZ_H_

#define _GNU_SOURCE
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>

/* The input as a NUL-terminated heap string of exactly size + 1 bytes, so
 * ASan catches a read past the terminator. */
static inline char *fuzz_strndup(const uint8_t *data, size_t size)
{
	char *s = malloc(size + 1);

	if (!s)
		abort();
	memcpy(s, data, size);
	s[size] = 0;
	return s;
}

/* The input as a readable file descriptor, positioned at its start. */
static inline int fuzz_memfd(const uint8_t *data, size_t size)
{
	int fd = memfd_create("fuzz", 0);

	if (fd < 0)
		abort();
	if (size && write(fd, data, size) != (ssize_t)size)
		abort();
	lseek(fd, 0, SEEK_SET);
	return fd;
}

#endif
