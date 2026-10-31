/* nix/fuzz/harness/c/fuzz_base64.c
 *
 * confd's base64_decode() (src/confd/src/base64.c) as its callers use it: the
 * keystore secrets for Wi-Fi (hardware.c, if-wifi.c) are decoded and then used
 * as C strings, so the result must be NUL-terminated.
 */
#include "fuzz.h"
#include "base64.c"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	unsigned char *out;
	size_t len;

	out = base64_decode(data, size, &len);
	free(out);

	out = base64_decode(data, size, NULL);
	if (out && strlen((char *)out) > size)
		abort();
	free(out);

	return 0;
}
