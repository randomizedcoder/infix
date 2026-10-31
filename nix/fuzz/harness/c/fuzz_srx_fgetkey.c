/* nix/fuzz/harness/c/fuzz_srx_fgetkey.c
 *
 * libsrx's key=value file reader (src/libsrx/src/helpers.c): fgetkey() on
 * the input as a file, then unquote() on an exact-size copy of every line,
 * as fgetkey does for the value it finds.
 */
#include "fuzz.h"
#include "helpers.c"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char path[64], *s, *line, *save = NULL;
	int fd;

	fd = fuzz_memfd(data, size);
	snprintf(path, sizeof(path), "/proc/self/fd/%d", fd);
	fgetkey(path, "ID");
	close(fd);

	s = fuzz_strndup(data, size);
	for (line = strtok_r(s, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
		char *copy = strdup(line);
		char *val = unquote(copy);

		(void)strlen(val);
		free(copy);
	}
	free(s);
	return 0;
}
