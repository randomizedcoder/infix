/* nix/fuzz/harness/c/fuzz_yangerd_frame.c
 *
 * statd's client side of the yangerd IPC (src/statd/yangerd.c): a 5-byte
 * header (version, 32-bit length), a JSON response, then an optional raw data
 * frame.  The input is what yangerd sends back.
 */
#include "fuzz.h"
#include "yangerd.c"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	size_t len = 0;
	char *buf = NULL;
	int fd = fuzz_memfd(data, size);

	if (yangerd_recv_response(fd, &buf, &len) == 0 && buf) {
		/* What statd does next: hand the data to libyang as a string. */
		if (strlen(buf) > len)
			abort();
	}
	free(buf);
	close(fd);
	return 0;
}
