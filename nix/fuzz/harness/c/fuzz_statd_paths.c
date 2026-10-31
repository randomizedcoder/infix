/* nix/fuzz/harness/c/fuzz_statd_paths.c
 *
 * statd's xpath helpers (src/statd/statd.c): sub_node_name() and
 * xpath_to_yangerd_path(), which copy part of a sysrepo xpath into a fixed
 * buffer.  The first input byte picks the buffer size, so the clamping is
 * tested at every size, 1 to 256.
 */
#include "fuzz.h"
#define main statd_main
#include "statd.c"
#undef main

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	size_t bufsz;
	char *path, *buf;

	if (size < 1)
		return 0;
	bufsz = (size_t)data[0] + 1;
	path = fuzz_strndup(data + 1, size - 1);
	buf = malloc(bufsz);

	sub_node_name(path, buf, bufsz);
	if (strlen(buf) >= bufsz)
		abort();
	xpath_to_yangerd_path(path, buf, bufsz);
	if (strlen(buf) >= bufsz)
		abort();

	free(buf);
	free(path);
	return 0;
}
