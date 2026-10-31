/* nix/fuzz/harness/c/fuzz_selftest.c
 *
 * Proves the libFuzzer + ASan toolchain catches an overflow.  It copies at
 * most SELFTEST_COPY_LEN bytes into an 8-byte heap buffer; the shipped value
 * is safe, and the fuzz-selftest check builds it with 32 and requires a crash.
 */
#include "fuzz.h"

#ifndef SELFTEST_COPY_LEN
#define SELFTEST_COPY_LEN 8
#endif

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char *buf = malloc(8);
	size_t n = size < SELFTEST_COPY_LEN ? size : SELFTEST_COPY_LEN;

	memcpy(buf, data, n);
	/* Keeps the compiler from dropping the unused copy. */
	__asm__ volatile("" : : "r"(buf) : "memory");
	free(buf);
	return 0;
}
