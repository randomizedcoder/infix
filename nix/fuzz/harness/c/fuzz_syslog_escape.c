/* nix/fuzz/harness/c/fuzz_syslog_escape.c
 *
 * The RFC 5424 escaping in confd's syslog RPC (src/confd/src/syslog.c), with
 * the buffer sizes its callers allocate: msgid_escape() into strlen * 2 + 1
 * (rpc_log), sd_escape() into strlen * 2 (sd_build's budget per value).
 * Exact-size heap buffers, so ASan sees any byte past that budget.
 */
#include "fuzz.h"
#include "syslog.c"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char *in = fuzz_strndup(data, size);
	size_t n = strlen(in);
	char *buf, *end;

	buf = malloc(n * 2 + 1);
	msgid_escape(in, buf);
	free(buf);

	buf = malloc(n * 2 + 1);
	end = sd_escape(buf, in);
	if ((size_t)(end - buf) > n * 2)
		abort();
	free(buf);

	free(in);
	return 0;
}
