/* nix/fuzz/harness/c/fuzz_journal_name.c
 *
 * statd's operational snapshot names (src/statd/journal_retention.c):
 * parse_timestamp_filename() on a directory entry name.
 */
#include "fuzz.h"
#include "journal_retention.c"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char *name = fuzz_strndup(data, size);
	time_t ts;

	parse_timestamp_filename(name, &ts);
	free(name);
	return 0;
}
