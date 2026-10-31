/* nix/fuzz/harness/c/fuzz_netd_config.c
 *
 * netd's static route and RIP configuration (src/netd/src/config.c), the
 * libconfuse files confd writes into /etc/netd/conf.d.  The input is one such
 * file; route and RIP parsing then runs on whatever libconfuse accepts.
 */
#include "fuzz.h"
#include "config.c"

/* As netd.c sets up a rip_config. */
static void rip_init(struct rip_config *cfg)
{
	memset(cfg, 0, sizeof(*cfg));
	TAILQ_INIT(&cfg->networks);
	TAILQ_INIT(&cfg->neighbors);
	TAILQ_INIT(&cfg->redistributes);
	TAILQ_INIT(&cfg->system_cmds);
}

#define FREE_ALL(head, type)					\
	do {							\
		struct type *e_;				\
		while ((e_ = TAILQ_FIRST(head))) {		\
			TAILQ_REMOVE(head, e_, entries);	\
			free(e_);				\
		}						\
	} while (0)

static void rip_free(struct rip_config *cfg)
{
	FREE_ALL(&cfg->networks, rip_network);
	FREE_ALL(&cfg->neighbors, rip_neighbor);
	FREE_ALL(&cfg->redistributes, rip_redistribute);
	FREE_ALL(&cfg->system_cmds, rip_system_cmd);
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	struct route_head routes = TAILQ_HEAD_INITIALIZER(routes);
	struct rip_config rip, ripng;
	char path[64];
	int fd;

	rip_init(&rip);
	rip_init(&ripng);
	fd = fuzz_memfd(data, size);
	snprintf(path, sizeof(path), "/proc/self/fd/%d", fd);
	config_parse_file(path, &routes, &rip, &ripng);
	close(fd);

	FREE_ALL(&routes, route);
	rip_free(&rip);
	rip_free(&ripng);
	return 0;
}
