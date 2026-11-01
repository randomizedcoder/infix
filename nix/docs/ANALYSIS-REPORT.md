# Infix analysis report: top 20 issues

Analysed commit: `2c084243` (fork `main`, upstream PR #1755 merge), 2026-10-31.

These findings come from running the deep analysis tier (`nix build .#analysis-report`),
the C and Go fuzzers (a 12 h campaign on a 24-thread host), `nix run .#vulncheck` and
`nix run .#secrets-scan`. About 60 of the top-scoring findings, plus anything
the fuzzers or vulncheck reported, were checked by reading the code. Only findings that
survived that check are listed. Every `file:line` refers to the analysed commit.

## Severity scale

| Severity | Meaning |
|---|---|
| Critical | Reachable from the network without authentication: memory corruption, command injection or an auth bypass |
| High | Reachable by an authenticated user, a container or a network neighbour: injection, or a crash of a network-facing daemon |
| Medium | A crash, leak or over-read that needs configuration access, or a weakness in crypto, session or authorisation handling |
| Low | Robustness and hardening |

No Critical issue was found. All of the webui is behind login, and none of the network
parsers that were fuzzed crashed.

## Summary

| # | Severity | Component | Location | Issue | Found by |
|---|---|---|---|---|---|
| 1 | High | confd | `src/confd/src/containers.c:318-319` | Container `command` written unquoted into a root shell script | semgrep, review |
| 2 | High | confd | `src/confd/src/cni.c:52-87` | Interface name from inside a container run through the host shell | semgrep, flawfinder, review |
| 3 | High | board | `board/common/signing-keys/development/infix.key` | Development RAUC signing key is public and trusted by 25 of 27 defconfigs | gitleaks, review |
| 4 | High | webui, netbrowse | `buildroot/package/go/go.mk:10` | Go 1.26.6 stdlib has reachable vulnerabilities | govulncheck |
| 5 | Medium | confd | `src/confd/src/base64.c:118` | `base64_decode()` output not NUL terminated (**fixed in kernelkit/infix#1762**) | libFuzzer + ASan |
| 6 | Medium | webui | `src/webui/internal/handlers/logs.go:38-50`, `diagnostics.go:302,474` | Logs and diagnostics bypass NACM and run as root | gosec, review |
| 7 | Medium | statd | `src/statd/avahi.c:436-479,510-519` | mDNS names from neighbours put unescaped into XPath predicates | review |
| 8 | Medium | confd | `src/confd/src/system.c:1403-1405` | Login shell string leaked for every user on every NACM change | clang-analyzer, review |
| 9 | Low | webui | `src/webui/internal/handlers/diagnostics.go` | Diagnostics run on GET; session cookie is `SameSite=Lax` | review |
| 10 | Low | bin | `src/bin/copy.c:575,608` | `scp -o StrictHostKeyChecking=no` for config transfers | semgrep, review |
| 11 | Low | webui | `src/webui/internal/server/middleware.go:103-106,129` | `sameOrigin` trusts `X-Forwarded-Host` and passes requests with no Origin | Go fuzz, review |
| 12 | Low | webui | `src/webui/internal/auth/store.go:20-25,78` | Plaintext password kept in the session store | gosec, review |
| 13 | Low | webui | `src/webui/internal/handlers/crypt.go:26` | md5crypt offered as a password hash | gosec |
| 14 | Low | webui | `src/webui/internal/restconf/client.go:69-84` | `checkPath` rejects `..` but not `%2e%2e` | review |
| 15 | Low | yangerd | `src/yangerd/` | No `recover()` anywhere: any goroutine panic kills the daemon | review |
| 16 | Low | klish | `src/klish-plugin-infix/src/infix.c:661-674,795-803` | Root file I/O in user homes; privileges dropped without `initgroups` | review |
| 17 | Low | klish, bin | `src/klish-plugin-infix/src/infix.c:707`, `src/bin/copy.c:243` | ssh/scp argv built from user input without `--` | review |
| 18 | Low | confd | `src/confd/src/containers.c:212,242`, `interfaces.c:835` | Loose YANG patterns on strings written to scripts and `ip -batch` | review |
| 19 | Low | confd | `src/confd/src/keystore.c:77` | SSH private key passed on the command line | flawfinder, review |
| 20 | Low | netbrowse | `src/netbrowse/main.go:66` | HTTP server has no read, write or idle timeouts | gosec |

## Details

### 1. High: container `command` becomes host root

`containers.c:318-319` writes the `command` leaf straight into
`/run/containers/<name>.sh`, a `#!/bin/sh` script that `package/confd/container` runs as
root on the host:

```c
if ((string = lydx_get_cattr(cif, "command")))
	fprintf(fp, " %s", string);
```

The YANG pattern for `command` (`infix-containers@2026-04-20.yang:264-268`) is
`[a-zA-Z0-9_./ :=@%^,${}()+-]+`, which allows `$(...)`.

- **Reach:** the factory NACM (`src/confd/share/factory.d/10-nacm.json`) sets
  `write-default: permit`, and `infix-containers` has no `nacm:default-deny-write`.
  `doc/nacm.md` says operators can configure the whole system, but not factory reset or
  upgrade. So an operator can set `command "$(id>/tmp/x)"` and run code as root on the
  host. `privileged true` gives the same result.
- **Fix:** quote each word (or exec with an argv), drop `$(){}` from the pattern, and add
  `nacm:default-deny-write` on `/containers`.

### 2. High: container interface name reaches the host shell

`cni.c:52-60` reads an interface name from inside the container's network namespace
(`container --net X find ifname PID`, which is `jq .ifname` at
`package/confd/container:967-969`). `cni_popen()` (`cni.c:72-87`) then formats it into
`ip -d -j link show dev %s ...` and runs it with
`popenf("re", "nsenter -t %d -n %s")`, which goes through `/bin/sh` on the host.

- **Reach:** root in a container with `CAP_NET_ADMIN` (YANG `capabilities add net_admin`,
  or `privileged`) can rename its `eth0` to `;reboot` or `$(poweroff)`, because the kernel's
  `dev_valid_name()` accepts `;$()|&`` ` ``. The next `iface_is_phys()`
  (`interfaces.c:56`) or `eth_gen_del()` (`interfaces.c:583`) then runs it as host root.
  This is a container escape.
- **Fix:** check the name against `^[A-Za-z0-9_.:+-]{1,15}$` before use, or exec
  `nsenter` and `ip` with an argv (libsrx `systemv.c` style).

### 3. High: the development signing key is trusted in production builds

The RAUC private key `board/common/signing-keys/development/infix.key` has been in the
tree since 2022 (`8716bea6`). 25 of 27 defconfigs set `IX_TRUSTED_KEYS_DEVELOPMENT=y`
(`board/common/Config.in:61-67`), so their images trust bundles signed with that key.

- **Reach:** the `install-bundle` RPC (`infix-system-software@2026-10-01.yang:346`) is
  admin only (`nacm:default-deny-all`) but accepts `http://` and `ftp://` URLs. An
  on-path attacker can swap in a bundle signed with the public development key and gets
  root on the next boot. `doc/` has no guidance on replacing the key.
- **Fix:** do not trust the development key in release defconfigs, or document clearly
  that products must replace it. Consider refusing unencrypted bundle URLs.

### 4. High: Go standard library 1.26.6

The image builds webui and netbrowse with Buildroot's Go 1.26.6. govulncheck at
`GOVERSION=go1.26.6` reports **13 reachable vulnerabilities in webui and 9 in
netbrowse**. The relevant ones for webui (HTTP/1.1 on 127.0.0.1 behind nginx):

| ID | Area |
|---|---|
| GO-2026-6609 | `net/http`: no limit on `Range` header parts |
| GO-2026-6608 | MIME header memory-limit bypass |
| GO-2026-6613 | HTTP/1 `CONNECT` request desync |
| GO-2026-6809 | `crypto/x509` |
| GO-2026-6607 | TLS ECH |
| GO-2026-6600, 6599 | `html/template` (no JavaScript-context data was found in the templates) |

The HTTP/2 server issues (6617, 6612, 6611, 6603) don't apply because webui doesn't serve
HTTP/2. The flake's own Go 1.26.9 hides all but GO-2026-6809, which is why `vulncheck`
pins Buildroot's version.

- **Fix:** bump `buildroot/package/go` to 1.26.10 or later.

### 5. Medium: `base64_decode()` output not NUL terminated, fixed

Found by the `fuzz_base64` libFuzzer harness within seconds:
`heap-buffer-overflow READ ... 0 bytes after 9-byte region`. `base64_decode()`
allocated exactly the decoded length (`base64.c:118`), and callers in `hardware.c`
(353, 661, 668, 677) and `if-wifi.c` (321, 522) use the result as a C string. Any secret
whose length is a multiple of three (no padding) was followed by heap garbage, so Wi-Fi
passphrases, SAE passwords and PPP passwords could be written to hostapd,
wpa_supplicant or pppd with extra characters.

- **Status:** fixed in kernelkit/infix#1762, with a table-driven unit test
  (`src/confd/src/base64-test.c`, 19 cases, run by `make check` and `make test-unit`).

### 6. Medium: webui logs and diagnostics bypass NACM

Most webui pages go through RESTCONF and so through NACM. The log viewer
(`logs.go:38-50,146,424`) and diagnostics (`diagnostics.go:302,474`) instead read files
and run tools inside the webui process, which runs as root (`webui.svc` sets no user).
The middleware order (`server.go:302-308`, `:440-443`) checks only that a session exists.

- **Reach:** any logged-in user, including one NACM limits to read-only, can read
  `/var/log/auth.log` and run nmap or traceroute from the device. The argv and log names
  are allowlisted, so this is not injection.
- **Fix:** gate these handlers on NACM group, or move them behind RESTCONF RPCs.

### 7. Medium: XPath injection from mDNS names

`statd/avahi.c:436-479,510-519` builds sysrepo XPaths such as
`/neighbor[hostname='%s']/address` from mDNS host and service names, without escaping.

- **Reach:** a LAN neighbour advertising a name with `'` or `]` can make edits fail,
  make statd drop the whole batch, or (with a crafted predicate) delete other
  neighbours' entries from operational data.
- **Fix:** build the nodes with `lyd_new_list()`, or escape with libsrx's `xpath_str`
  helpers.

### 8. Medium: shell string leaked on NACM changes

`system.c:1403-1405` gets a `strdup()`ed shell from `sys_find_usable_shell()` for every
user each time NACM changes, and never frees it. A long-running device with frequent
NACM edits grows confd's heap without bound.

- **Fix:** `free()` the shell after `set_shell()`.

### 9. Low: diagnostics on GET, `SameSite=Lax`

`GET /maintenance/diagnostics/run?tool=nmap&target=X` runs the tool. The CSRF check
skips GET (`middleware.go:81-84`) and the session cookie is `SameSite=Lax`
(`login.go:99-106`), so a link on another site can start a scan from the device.

- **Fix:** make it a POST, or use `SameSite=Strict`.

### 10. Low: `StrictHostKeyChecking=no` for config transfer

`copy.c:575,608` run `scp -o StrictHostKeyChecking=no`, so a man in the middle can
receive a pushed configuration (with password hashes and keys) or supply a pulled one.

- **Fix:** use the user's `known_hosts`, as the CLI `ssh` already does.

### 11. Low: `sameOrigin` trusts `X-Forwarded-Host`

`middleware.go:103-106` compares Origin against `X-Forwarded-Host`, which nginx passes
through from the client, and `:129` returns true when Origin and Referer are both
missing. The CSRF token (`:132-142`, an `HttpOnly`, `Strict` cookie) still blocks
cross-site posts, so this weakens one layer only.

- **Fix:** compare against the configured host, and treat a missing Origin as cross-site
  for unsafe methods.

### 12. Low: plaintext password in the session store

`auth/store.go:20-25,78` keeps each user's password in memory for the session lifetime,
to re-authenticate to RESTCONF on every request.

- **Fix:** keep a RESTCONF token or a derived credential instead.

### 13. Low: md5crypt offered

`crypt.go:26` lists md5crypt (and sha256crypt) as a choice when setting a password; yescrypt is the default.

- **Fix:** offer only sha512crypt and yescrypt.

### 14. Low: `checkPath` misses encoded dot segments

`restconf/client.go:69-84` rejects `..` in a RESTCONF path but not the encoded form `%2e%2e`.

- **Fix:** decode before checking, or reject `%2e` as well.

### 15. Low: yangerd has no panic recovery

yangerd has no `recover()` anywhere, so a panic in any monitor goroutine (for example
while parsing a netlink or D-Bus message) kills the daemon until finit restarts it. The
fuzzers found no panic in the 16 yangerd targets.

- **Fix:** recover in each monitor goroutine, log and restart that monitor.

### 16. Low: klish plugin root file handling

- `infix.c:661-674` `ensure_known_hosts()` creates `~/.ssh/known_hosts` as root in a
  directory the user's home path controls.
- `infix.c:719-748` reads the user's `known_hosts` as root.
- `infix.c:795-803` drops privileges with `setgid`/`setuid` but no `initgroups()`, so the
  root supplementary groups are kept.
- `cd_home()` (`infix.c:34-49`) falls back to root's home.

Each needs a local shell to exploit. **Fix:** do the file work after dropping
privileges, and call `initgroups()`.

### 17. Low: ssh/scp argv without `--`

`infix.c:707` and `copy.c:243` put a user-supplied host or path into the ssh/scp argv
without `--`, so a value starting with `-` (for example `-oProxyCommand=...`) is read as
an option. The CLI user already has those rights, so this is hardening.

- **Fix:** add `--` before the host argument, and reject leading `-`.

### 18. Low: loose patterns on strings written to scripts

- `containers.c:212`: the mount `source` pattern allows spaces, so a source can add
  arguments to the wrapper script (it must name an existing file).
- `containers.c:242`: the `env` value has no pattern, so a newline adds environment
  variables inside the container.
- `interfaces.c:835`: the interface `description` may contain `"`, which ends the
  `link set alias "..."` line written to `ip -batch` (no shell is involved).

**Fix:** tighten the YANG patterns, and quote in the writers.

### 19. Low: private key on argv

`keystore.c:77` calls `mksshkey` with the private key as an argument, so it is visible
in `/proc/*/cmdline` while the command runs.

- **Fix:** pass it on stdin or through a file with mode 0600.

### 20. Low: netbrowse has no server timeouts

`netbrowse/main.go:66` creates an `http.Server` with no `ReadHeaderTimeout`, so slow
clients can hold connections open (gosec G112).

- **Fix:** use an `http.Server` with read, write and idle timeouts.

## Also noted

- `hardware.c:432,466`: `realloc()` result not checked.
- `dagger.c:104-106`: `readlink()` into `sizeof(path)` then `path[len] = 0`, one byte
  past the end when the link fills the buffer.
- `journal.c:75` and `frrconf_backend.c:212` don't check `ferror()`, so a write error
  truncates silently.
- `src/.clang-format` has duplicate keys, which clang-format 21 rejects.
- libsrx `fgetkey()` returns a static buffer, which is not reentrant.
- `test/docker/pip-requirements.txt`: urllib3 2.7.0 (3 advisories, fixed in 2.8.0),
  certifi, lxml, requests and idna have advisories. This only affects the test
  container.

## False positives

These were checked and dropped; the matching patterns are in
`nix/analysis/triage/exemptions.txt`.

- **confd shell calls:** `firewall.c:145,173` (inet types only), `system.c` user names
  (pattern-restricted), the hardware country code (an enum), interface names (pattern
  `[a-zA-Z0-9_][a-zA-Z0-9_.:+-]*`, length 1-15), `modem.c:60` (a constant).
- **confd buffers:** `interfaces.c:272` `strcpy` (MAC address, 17 chars into 18),
  `dhcp-common.c:178` `strcat` after `realloc`, `syslog.c:603,605` (sized `sprintf`).
- **clang-analyzer:** avahi use-after-free and double free (`LIST_REMOVE` aliasing),
  hardware double frees, `pppmon` array bounds (netlink idiom), `locate.c:77`,
  `support.c:148`, `if-qos.c:434`, NULL arguments that YANG keys or defaults guarantee,
  leaks at exit in `main.c`.
- **webui:** `isPublicPath("/assets/../")` (the mux redirects cleaned paths),
  `dashboard.go:954` (`ParseIP` and zone checked), diagnostics argv (allowlisted),
  `crypt.go:56` (password on stdin), `InsecureSkipVerify` (flag only).
- **klish, netd:** constant `shellf()` strings, `netd.c:163` and `vtysh_backend.c:343`
  (literals).
- **gitleaks:** 48 hits; all but the development key are `curl -u` examples in the docs,
  test keys and the `mksshkey` template.

## Appendix A: fuzzing

### C (libFuzzer, ASan + UBSan)

12 h campaign on l3 (24 threads), 6 harnesses at 3,000 s each with 14 forks:

| Harness | Target | Executions | Crashes |
|---|---|---|---|
| `fuzz_journal_name` | `journal_retention.c` timestamp names | 1.23 B | 0 |
| `fuzz_statd_paths` | statd `xpath_to_yangerd_path`, `sub_node_name` | 1.03 B | 0 |
| `fuzz_syslog_escape` | confd `sd_escape`, `msgid_escape` | 598 M | 0 |
| `fuzz_yangerd_frame` | statd `yangerd_recv_frame`, `yangerd_recv_response` | 100 M | 0 |
| `fuzz_srx_fgetkey` | libsrx `fgetkey`, `unquote` | 91 M | 0 |
| `fuzz_netd_config` | netd route and RIP config parsing | 19 M | 0 |
| `fuzz_base64` | confd `base64_decode` | | issue 5 only |

### Go (native fuzzing)

21 targets at 2,000 s each, 13 M to 168 M executions per target, 0 failures. The
targets cover yangerd `ipc`, `zapi`, `wpactrl`, `iwmonitor`, `ptpmonitor`,
`lldpmonitor`, `dbusmonitor` and `iface` parsers, and webui `sameOrigin`, `validCSRF`,
`isPublicPath`, `diagCommand` and `validTarget`.

## Appendix B: tool counts

Raw finding counts from `analysis-deep`, before triage:

| Tool | Count | Tool | Count |
|---|---|---|---|
| clang-tidy | 2141 | gosec | 359 |
| clang-format | 1825 | ruff | 354 |
| golangci-comprehensive | 1334 | cppcheck | 153 |
| shellcheck | 1087 | semgrep | 98 |
| cppcheck-exhaustive | 541 | codechecker | 40 |
| flawfinder | 522 | gcc-analyzer | 25 |
| bandit | 522 | gofmt | 21 |
| golangci | 364 | yanglint | 8 |
| go-vet, go-race, nix-lint | 0 | | |

## Appendix C: commands

```sh
nix build .#analysis-report       # deep tier + triage: result/top.txt, findings.json, triage.md
nix build .#fuzz-run              # 20 s per C harness
FUZZ_DEEP_TIME=3000 FUZZ_DEEP_FORKS=14 nix run .#fuzz-deep
FUZZ_TIME=2000 nix run .#fuzz-go-run
nix run .#vulncheck               # govulncheck at Buildroot's Go, osv-scanner
nix run .#secrets-scan            # gitleaks over the git history
```
