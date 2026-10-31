# Infix — Nix flake

This directory holds a modular [Nix](https://nixos.org) setup for working on Infix's own
code in `src/`: about 33k lines of C (confd, statd, netd, libsrx, bin, the klish plugin),
about 63k lines of Go (yangerd, webui, netbrowse, features), and the Python and shell
around them. One command gives you a shell with every library and tool. Others build the
C and Go code on the host, run static analysis in three tiers, fuzz the parsers, and rank
every finding.

## Goals

- **Easy onboarding:** build and check `src/` on any Linux distro without installing
  libyang, sysrepo, klish or a dozen analysis tools by hand.
- **Reproducibility:** `flake.lock` pins every input (nixpkgs, Buildroot, the tools), so a
  build or a finding means the same thing on every machine.
- **Deep checks:** CodeChecker with cross-TU analysis, `gcc -fanalyzer`, cppcheck, semgrep,
  gosec, golangci-lint, libFuzzer and Go native fuzzing, with one ranked report.
- **No effect on the host:** nothing is installed system-wide. Tools exist only inside
  `nix develop` or a `nix build`/`nix run`.

What it does **not** replace: Buildroot still builds the images (`make x86_64_defconfig &&
make`). The flake gives Buildroot a known-good host environment (`nix develop .#buildroot`,
below), and it builds `src/` on the host for fast checks, but the image you flash is still
Buildroot's.

> ⚠️ **Linux only.** The flake lives on the `nix-flake` branch of
> [randomizedcoder/infix](https://github.com/randomizedcoder/infix/tree/nix-flake). It is
> not part of upstream.

- **Design and rationale:** [`docs/DESIGN.md`](docs/DESIGN.md)
- **Status and follow-ups:** [`STATUS.md`](STATUS.md)
- **The top 20 issues found:** [`docs/ANALYSIS-REPORT.md`](docs/ANALYSIS-REPORT.md)

---

## Quick start

### 1. Install Nix

Pick a **multi-user** (daemon) or **single-user** install:

- [Multi-user](https://nix.dev/manual/nix/2.24/installation/#multi-user), recommended on most
  distros:
  ```sh
  bash <(curl -L https://nixos.org/nix/install) --daemon
  ```
- [Single-user](https://nix.dev/manual/nix/2.24/installation/#single-user), no daemon, with the
  store owned by your user:
  ```sh
  bash <(curl -L https://nixos.org/nix/install) --no-daemon
  ```

#### Video walkthroughs

| Platform | Video |
|---|---|
| Ubuntu | [Installing Nix on Ubuntu](https://youtu.be/cb7BBZLhuUY) |
| Fedora | [Installing Nix on Fedora](https://youtu.be/RvaTxMa4IiY) |

### 2. Enable flakes (once)

```sh
test -d /etc/nix || sudo mkdir /etc/nix
echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf
```

Or per command: `nix --extra-experimental-features 'nix-command flakes' develop`.
See also the [Nix flakes wiki](https://nixos.wiki/wiki/flakes).

Need a tool just once? `nix shell nixpkgs#<tool> -c <command>` runs it without installing
it, e.g. `nix shell nixpkgs#jq -c jq . result/findings.json`.

### 3. Get the code and enter the dev shell

```sh
git clone -b nix-flake https://github.com/randomizedcoder/infix.git
cd infix
nix develop
```

The first run downloads and builds the dependencies (libyang, sysrepo, klish), which takes
a few minutes. After that they come from `/nix/store` and the shell starts in seconds.
`infix-help` lists the helper functions:

```sh
infix-host-build            # configure + make every C component into output-host/
infix-host-build confd      # ... or just one
infix-go-test               # go test -race in every Go module
infix-check quick           # nix build .#analysis-quick and print the summary
infix-fuzz 60               # build the C fuzzers and run each for 60 s
infix-report                # the ranked findings of the deep tier and the fuzz runs
```

`infix-host-build` works on a copy under `output-host/build/`, so `src/` stays clean.

### 4. Try it: a check, the fuzzers, the report

```sh
nix build .#analysis-quick && cat result/summary.txt
nix build .#fuzz-run       && cat result/summary.txt
nix build .#analysis-report && less result/triage.md
```

Each `nix build` leaves a `result` symlink to its output in `/nix/store`. It is read-only;
copy what you want to keep. `nix build --out-link my-name .#X` picks another name, and
`--no-link --print-out-paths` prints the path without a link.

---

## All commands

Typical times are on a 24-core machine with a warm store; the first build of anything
takes longer.

### Dev shells

| Command | What it gives you |
|---|---|
| `nix develop` | the C libraries (including the pinned libyang, sysrepo and klish), autotools, Go 1.26, gopls, Python, every analysis tool, and the `infix-*` helpers |
| `nix develop .#buildroot` | an FHS environment with Buildroot's host prerequisites: `make x86_64_defconfig && make`, `make test` |
| `nix run .#buildroot -- <cmd>` | one command in that environment, e.g. `nix run .#buildroot -- make x86_64_defconfig` |

### Builds

| Command | Output | Time |
|---|---|---|
| `nix build .#infix-c` | every C component (release), merged | 2 min |
| `nix build .#infix-c-debug` | the same, `-O0 -g3` | 2 min |
| `nix build .#infix-c-asan` | the same with ASan + UBSan (clang) | 2 min |
| `nix build .#infix-c-cov` | the same with gcov instrumentation | 2 min |
| `nix build .#confd` (`statd`, `netd`, `libsrx`, `bin`, `klish-plugin-infix`, `gencert`, `keyack`, `factory`, `test-mode`, `rauc-installation-status`) | one component | < 1 min |
| `nix build .#webui` (`yangerd`, `netbrowse`, `features`) | one Go module | < 1 min |
| `nix build .#go-test` | `go test -race ./...` in every Go module | 3 min |
| `nix build .#go-test-<module>` | ... in one module | 1 min |
| `nix build .#libyang` (`sysrepo`, `faux`, `klish`) | the pinned dependencies | 1–3 min |
| `nix build .#compile-db` | the configured C sources with `compile_commands.json` | 2 min |

### Static analysis

| Command | Adds | Time |
|---|---|---|
| `nix build .#analysis-quick` | clang-format, shellcheck, ruff, gofmt, go vet, yanglint, nixpkgs-fmt/statix/deadnix | 1 min |
| `nix build .#analysis-standard` | + cppcheck, clang-tidy, flawfinder, bandit, golangci-lint, gosec | 5 min |
| `nix build .#analysis-deep` | + CodeChecker (cross-TU), gcc `-fanalyzer`, cppcheck exhaustive, semgrep, golangci comprehensive, `go test -race` | 20 min |
| `nix build .#analysis-<tool>` | one tool, e.g. `.#analysis-codechecker` | varies |
| `nix build .#analysis-report` | the deep tier + the fuzz runs, scored and ranked | deep + 2 min |

Each tool's directory has `report.txt` (one finding per line, `file:line:col: severity:
message [check]` where the tool allows), `count.txt`, and the tool's native output where
it has one (`report.json`, `.sarif`, `.xml`). A tier adds `summary.txt` with every tool's
count. The report adds `findings.json`, `top.txt` and `triage.md`.

### Fuzzing

| Command | What it does | Time |
|---|---|---|
| `nix build .#fuzz` | the C harnesses (libFuzzer, ASan, UBSan) and `bin/run-fuzzers` | 1 min |
| `FUZZ_TIME=300 ./result/bin/run-fuzzers [outdir]` | run each harness for 5 minutes | |
| `nix build .#fuzz-run` | each C harness for 20 s → `summary.txt`, `count.txt`, `report.txt`, `crashes/` | 3 min |
| `nix run .#fuzz-deep -- [outdir]` | fork mode and the dictionaries; `FUZZ_DEEP_TIME` (60 s), `FUZZ_DEEP_FORKS` (2) | |
| `nix build .#fuzz-cov` | per-function coverage the harnesses reach in 20 s | 3 min |
| `nix build .#fuzz-selftest` | fails unless a planted overflow is caught (a check) | 1 min |
| `nix build .#fuzz-go-run` | each Go fuzz target for 10 s | 5 min |
| `nix run .#fuzz-go -- [outdir]` | each Go fuzz target for `FUZZ_TIME` seconds (60) | |

### Commands that need the network or the live tree

| Command | What it does |
|---|---|
| `nix run .#vulncheck -- [outdir]` | govulncheck per Go module, at the Go version Buildroot builds the image with, and osv-scanner over every lock file |
| `nix run .#secrets-scan -- [outdir]` | gitleaks over the whole git history |
| `nix run .#deps-drift` | compares `nix/deps/pins.nix` with Buildroot's `.mk` files and the buildroot submodule |

### Checks and housekeeping

```sh
nix flake check     # analysis-quick, infix-c, go-test-*, fuzz-selftest, triage tests, deps-drift
nix flake show      # every output
nix fmt             # nixpkgs-fmt over the Nix files
```

---

## Static analysis

### The tiers

Each tier runs every tool of the tier below it plus its own. `quick` is cheap enough for
every commit (it is a `nix flake check`); `standard` is for a branch before review;
`deep` takes longest and finds the path-sensitive bugs: use-after-free, double free,
NULL dereferences across functions and files.

The C tools read a compile database ([`build/compile-db.nix`](build/compile-db.nix)): each
component is configured with the flags Buildroot uses and built under `bear`, so every
tool sees the same defines and include paths as the real build.

The Go tools run on each module's vendored source, offline. The golangci-lint configs are
in [`analysis/go/`](analysis/go/), so `src/` is unchanged.

The semgrep rules in [`analysis/semgrep-rules.yaml`](analysis/semgrep-rules.yaml) target
Infix's own risks: `systemf()`/`popenf()` with `%s`, `strcpy`/`sprintf`, Go `exec.Command`
fed from a request, path joins with request values, and token comparisons.

### How findings are ranked

[`analysis/triage/`](analysis/triage/) reads every `report.txt`, drops third-party code,
tool noise and the verified false positives in
[`triage/exemptions.txt`](analysis/triage/exemptions.txt), merges duplicates, and scores
each finding:

```
score = severity (error 3, warning 2, style 1)
      × class    (injection 10, memory safety 9, auth/crypto 7, path traversal 7,
                  resource 4, correctness 3, style 1)
      × exposure (webui 3, yangerd/netbrowse 2.5, statd/confd/libsrx 2, netd/klish 1.5, …)
      × 1.5 when two different analyzers flag the same place
```

`top.txt` lists the highest scores; `triage.md` groups them by class and component.
A high score means "read this first", not "this is a bug": every entry in
[`docs/ANALYSIS-REPORT.md`](docs/ANALYSIS-REPORT.md) was checked by reading the code.

### Adding a tool

Write `analysis/<tool>.nix` as one `mkAnalysisTool` call (see
[`analysis/default.nix`](analysis/default.nix) for the arguments), add it to `tools` and to
a tier list there, and, if its `report.txt` is not in the gcc format, add a parser to
[`triage/parsers.py`](analysis/triage/parsers.py) with a test row in `test_triage.py`.

### A false positive

Read the code first. If the finding is wrong, add a line to
[`triage/exemptions.txt`](analysis/triage/exemptions.txt):

```
src/confd/src/locate.c:77 security.ArrayBound  # bounded by the len < sizeof(buf) - 1 loop
```

The reason is mandatory; triage refuses a line without one.

---

## Fuzzing

### C harnesses

Each harness in [`fuzz/harness/c/`](fuzz/harness/c/) `#include`s the `.c` file it tests,
compiled with that file's own flags from the compile database, so `static` functions are
reachable and `src/` is unchanged. Functions the file calls in the component's other files
become stubs that trap; the harness never reaches them.

| Harness | Target |
|---|---|
| `fuzz_yangerd_frame` | statd ↔ yangerd IPC framing: `yangerd_recv_frame`, `yangerd_recv_response` |
| `fuzz_statd_paths` | statd `xpath_to_yangerd_path`, `sub_node_name` |
| `fuzz_syslog_escape` | confd `msgid_escape`, `sd_escape` |
| `fuzz_netd_config` | netd's libconfuse config parser (`parse_route_section`, `parse_rip_section`) |
| `fuzz_srx_fgetkey` | libsrx `fgetkey`, `unquote` |
| `fuzz_journal_name` | statd `parse_timestamp_filename` |
| `fuzz_base64` | confd `base64_decode`, which Wi-Fi secrets go through |
| `fuzz_selftest` | a planted overflow, to prove the toolchain catches one |

### Go targets

[`fuzz/harness/go/<module>/<package>/fuzz_test.go`](fuzz/harness/go/) is copied into the
module's vendored source at build time. Targets: yangerd's IPC, ZAPI, wpa_supplicant,
LLDP, dnsmasq lease, PTP, nl80211 and VLAN decoders, and webui's origin, CSRF,
public-path and diagnostics checks (as property tests).

### Reproducing a crash

`fuzz-run` and `fuzz-deep` put crash inputs under `crashes/<harness>/` and one line per
distinct crash in `report.txt`. To replay one:

```sh
nix build .#fuzz
./result/bin/fuzz_netd_config path/to/crash-…      # prints the sanitizer report
```

For Go, the failing input is copied to `crashes/<module>/<Target>/`; put it under
`testdata/fuzz/<Target>/` in the package and run `go test -run=<Target>`.

### Adding a harness

- **C:** write `fuzz/harness/c/fuzz_<name>.c` (it includes `src/<file>.c`), add
  `<name> = "<file under src/>";` to `harnesses` in [`fuzz/default.nix`](fuzz/default.nix),
  and put a few seed inputs in `fuzz/corpus-seeds/<name>/`. A dictionary is optional:
  `fuzz/dict/<name>.dict`.
- **Go:** write `fuzz/harness/go/<module>/<package>/fuzz_test.go` with `func FuzzX(f
  *testing.F)`; the runner finds every `Fuzz*` function itself.

Check the coverage with `nix build .#fuzz-cov`: a function at 0% means the seeds or the
harness never reach it.

---

## The Buildroot FHS shell

Buildroot expects a conventional `/usr` layout and refuses some of the variables a Nix
shell sets. `nix develop .#buildroot` starts an FHS environment
([`dev/buildroot-fhs.nix`](dev/buildroot-fhs.nix)) with the host packages listed in
`doc/developers-guide.md`:

```sh
git submodule update --init
nix develop .#buildroot
make x86_64_defconfig
make
make test           # needs podman or docker on the host
```

Or one command at a time: `nix run .#buildroot -- make x86_64_defconfig`.

---

## Updating the pins

- **nixpkgs and the tools:** `nix flake update`, then `nix flake check`.
- **Buildroot bumped** (the submodule moved): update the `buildroot` input's commit in
  [`../flake.nix`](../flake.nix), run `nix flake lock`, then `nix run .#deps-drift`. It
  says which of libyang, sysrepo, faux and klish moved. Update their versions in
  [`deps/pins.nix`](deps/pins.nix), set each `hash` to `""`, build `.#libyang` (and the
  others), and copy the hash from the error into `pins.nix`.
- **A Go module's dependencies changed:** the build fails with a `vendorHash` mismatch.
  Copy the `got:` hash into `vendorHashes` in [`build/go.nix`](build/go.nix).

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `error: experimental Nix feature 'nix-command' is disabled` | enable flakes (step 2), or add `--extra-experimental-features 'nix-command flakes'` |
| `hash mismatch in fixed-output derivation` … `got: sha256-…` | a pinned source or `vendorHash` changed; put the `got:` hash in the file named above |
| a new file is not seen by a build | flakes only see files git knows: `git add -N <file>` |
| `No space left on device` in a build | the deep tier and the fuzzers use several GB of `/tmp`; `nix-collect-garbage -d` frees old store paths |
| `nix develop .#buildroot` then `make` complains about the environment | run `make` inside the FHS shell, not in `nix develop` |
| `make test` cannot start containers | the FHS shell uses the host's podman/docker; check `podman info` outside it first |
| `vulncheck` or `secrets-scan` fail at once | they need the network (vulnerability databases) and a git checkout |

---

## How to read this tree

New to Nix? Four ideas cover most of what is here.

- **A derivation is a build recipe.** It lists its inputs (source, compilers, other
  derivations) and a script that writes its output to `/nix/store/<hash>-<name>`. The hash
  covers every input, so the same inputs give the same output on any machine, and a build
  whose inputs have not changed is not run again.
- **A `.nix` file is usually a function.** `{ pkgs, lib, infixLib }: ...` takes an attribute
  set (Nix's name for a record or dict) and returns derivations. The braces list what the
  file depends on.
- **The scope wires the files together.** [`scope.nix`](scope.nix) calls each file with
  `callPackage`, which passes it the arguments its braces name, from the scope or from
  nixpkgs. No file imports another file's dependencies by hand.
- **The flake exposes the results.** [`../flake.nix`](../flake.nix) names its inputs
  (nixpkgs, flake-parts, Buildroot, all pinned in `flake.lock`) and lists the files in
  [`parts/`](parts/). Each part picks targets from the scope, and those are the names that
  `nix build .#<name>` and `nix run .#<name>` accept.

A few more words you will meet:

- **The store** (`/nix/store`) holds every build output, read-only, named by its hash.
- **A `result` link** is the symlink `nix build` leaves to the output it built.
- **A devShell** is the environment `nix develop` enters: the inputs of a derivation, without
  building it.
- **flake-parts** splits `flake.nix` into modules (`parts/`), one per area.

So, to find where `nix build .#X` comes from, look in `parts/` for the area, then in the
scope for the file.

## Folder map

| Folder | What it holds |
|---|---|
| [`parts/`](parts/) | the flake's outputs, one file per area ([README](parts/README.md)) |
| [`lib/`](lib/) | `infixLib`: source subsets of the tree, version, meta |
| [`deps/`](deps/) | libyang, sysrepo (with Buildroot's and Infix's patches), faux and klish at Buildroot's versions |
| [`build/`](build/) | host builds of the C components and Go modules, the compile database |
| [`dev/`](dev/) | `nix develop`, the Buildroot FHS shell, the `infix-*` helpers |
| [`analysis/`](analysis/) | one file per tool, the tiers, semgrep rules, golangci configs, `triage/` |
| [`fuzz/`](fuzz/) | C and Go harnesses, seeds, dictionaries, the runners |
| [`apps/`](apps/) | `vulncheck`, `secrets-scan`, `deps-drift` |
| [`docs/`](docs/) | [`DESIGN.md`](docs/DESIGN.md), [`ANALYSIS-REPORT.md`](docs/ANALYSIS-REPORT.md) |
| [`versions.nix`](versions.nix) | the toolchains and tools, in one place |
