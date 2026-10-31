# Design of the Infix Nix flake

This page explains why the flake is built the way it is. [`../README.md`](../README.md)
covers how to use it.

## What it is for

Buildroot builds the Infix images, and the flake does not replace it. The flake is a
reproducible layer for working on the project's own code in `src/` from any Linux host
with Nix:
- host builds of the C and Go code, with sanitizer and coverage variants;
- static analysis in tiers;
- fuzzing;
- a dev shell, and an FHS shell that Buildroot itself runs in.

Every tool is pinned through `flake.lock`, so a finding reproduces on another machine.

## Principles

- **`src/` never changes.** A tool that needs config, a harness that needs a `static`
  function, or a build that needs a flag gets it from the Nix side:
  - golangci configs live in `analysis/go/`;
  - harnesses `#include` the file they test;
  - Go fuzz tests are copied into a copy of the module.
- **The pins come from the tree.** libyang, sysrepo (with the patches in `patches/sysrepo/`),
  faux and klish are built at the versions in `buildroot/package/*.mk` and `package/*.mk`.
  The `deps-drift` check fails when the flake and the tree disagree, so a Buildroot bump
  cannot silently leave the host builds analysing different libraries.
- **One file per tool, one part per area.** The build logic lives in plain `callPackage`
  files under `nix/<area>/`, collected by `scope.nix`. The flake-parts files in `parts/`
  only select outputs. This is the HomaModule layout; see [`../parts/README.md`](../parts/README.md).
- **Small sources.** `lib/` gives each derivation only the part of the tree it reads
  (`srcFor`), so editing confd does not rebuild webui or rerun the Go linters.
- **Builds in the sandbox, apps outside it.** Everything that can run offline is a
  derivation, so Nix caches it and `nix flake check` can run it. Three things are apps
  (`nix run`) instead:
  - `vulncheck`, which needs the vulnerability databases;
  - `secrets-scan`, which needs the git history;
  - `fuzz-deep` and `fuzz-go`, which take their run time from the environment.

## Host builds

`build/c.nix` builds each C component the way its Buildroot package configures it, but
with every optional feature on, so the analysis sees all of the code. libsrx installs
first, and the other components build against it.

There are four variants:
- release;
- debug;
- ASan + UBSan, built with clang;
- gcov.

`build/compile-db.nix` runs the release build under bear. It keeps each configured tree
next to its `compile_commands.json`, because the C analysers need the generated
`config.h` as well as the flags. `passthru.setup` copies the trees into any build directory
and rewrites the paths, so every C tool works on the same view of the code.

`build/go.nix` vendors each Go module once. The vendored tree (`vendoredSource`) is what
these run on, offline:
- `go test`;
- the Go linters;
- the Go fuzz targets.

This is the xtcp2 `goModules` pattern.

## Analysis

Each tool is one `mkAnalysisTool` call (`analysis/default.nix`). It writes a
`report.txt` in the GCC diagnostic format (`file:line:col: severity: message [check]`),
plus the tool's native JSON, XML or SARIF output where it has one. It also writes
`count.txt`. A tier copies its tools' outputs together and sums the counts. Writing one
common text format keeps the triage parsers small, and each tool can be read without
triage.

`analysis/semgrep-rules.yaml` holds local rules, because the sandbox cannot reach the
semgrep registry. They look for the patterns that matter in this code base:
- `systemf`, `popenf`, `fopenf` and `run` with a `%s` argument;
- unbounded copies;
- Go `exec.Command` and `filepath.Join` with values taken from a request;
- token comparisons that are not constant-time.

### Triage

`analysis/triage/` is ported from xdp2. It runs these steps in order:
1. It parses every `report.txt`.
2. It drops vendored code, generated code, test code and the entries listed in
   `exemptions.txt`. Each exemption needs a reason.
3. It removes duplicates on file, line and check.
4. It scores each finding as **severity × class × exposure**, and multiplies the score by
   1.5 when two tools agree.
   - The class weights rank injection and memory safety above auth and crypto, which rank
     above resource handling, which ranks above style.
   - Exposure comes from the path. Code that faces the network or a neighbour (webui,
     yangerd, statd IPC, the Wi-Fi, LLDP and DHCP parsers) ranks above confd, which only
     configuration reaches. confd ranks above the CLI and the tools.

The score only sets the order of reading. Every entry in the report was checked against
the code.

## Fuzzing

The C harnesses follow HomaModule's pattern:
- Each `harness/c/fuzz_<name>.c` `#include`s the `.c` file it tests, compiled with that
  file's flags from the compile database (`tools/db-flags.py`). This makes the `static`
  parsers reachable without exporting them.
- When the link fails, the undefined symbols each get a stub that traps (`build_harness`
  in `fuzz/default.nix`). The harness does not need the rest of the component, and a stub
  that is reached by mistake shows up as a crash instead of a silent pass.
- `fuzz-selftest` builds a planted overflow and fails unless ASan catches it. This stops
  a toolchain change from quietly disabling the sanitizers.

`tools/run-fuzzers.sh` runs every harness, reproduces each crash input and keeps one per
sanitizer `SUMMARY` line. It writes that crash into `report.txt` at its first stack frame
under `src/`, so triage scores fuzz crashes like any other finding.

The Go targets are ordinary `testing.F` fuzz tests. They live in `harness/go/` and are
copied into the vendored module at build time.

## Follow-ups this design leaves room for

- More C harnesses, for the confd XPath and IPC paths that need a libyang context.
- Running `analysis-deep` in CI with the reports kept as artifacts, and failing only on
  new findings.
- A `nix run .#ci` that matches the GitHub workflows.
