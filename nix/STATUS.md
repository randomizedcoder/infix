# Status

As of 2026-10-31, on the fork's `nix-flake` branch.

## Works

- `nix develop`, `nix develop .#buildroot`, and `nix fmt`.
- Host builds:
  - libsrx, confd, statd, netd, bin, factory, keyack, gencert and klish-plugin-infix,
    each in the release, debug, ASan + UBSan and gcov variants;
  - webui, yangerd, netbrowse and features, with `go test -race`.
- Pinned dependencies, with `deps-drift` checking them against the tree: libyang 6.4.13,
  sysrepo 5.2.27 (with its patches), faux and klish.
- `analysis-quick`, `-standard` and `-deep`: 19 tools, plus `analysis-report` (triage).
  The triage unit tests are a flake check.
- Fuzzing:
  - 8 C libFuzzer harnesses, with `fuzz-selftest` as a check;
  - 21 Go fuzz targets;
  - `fuzz-cov`.
- `vulncheck` (govulncheck at Buildroot's Go version, and osv-scanner), `secrets-scan`
  (gitleaks).

## Findings

The top 20 are in [`docs/ANALYSIS-REPORT.md`](docs/ANALYSIS-REPORT.md). The fuzzers found
one bug, in confd `base64_decode` (fixed in kernelkit/infix#1762); the others ran clean.

## Known gaps

- `src/.clang-format` has duplicate keys that clang-format 21 rejects, so the
  clang-format tool runs with a copy that has them removed.
- `patches/libyang/3.13.5/` is stale: Buildroot is at libyang 6.4.13. `deps-drift` warns
  about it.
- No C harness yet covers the confd XPath and callback code that needs a libyang
  context.
- netbrowse and features have no fuzz targets.
- `vulncheck` and `secrets-scan` need the network or the git history, so they are not
  flake checks.
