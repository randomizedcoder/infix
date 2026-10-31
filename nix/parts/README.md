# nix/parts

`flake.nix` is a [flake-parts](https://flake.parts) flake: it lists these files in
`imports`, and each one adds the outputs of one area. The parts hold no build logic.
They take the package scope that [`scope.nix`](scope.nix) builds once per system (the
`infix` argument, from [`../scope.nix`](../scope.nix)) and pick outputs out of it, so
the build code can be read, and `callPackage`d, without knowing flake-parts.

| Part | Adds | From |
|---|---|---|
| [`scope.nix`](scope.nix) | the perSystem argument `infix` | [`../scope.nix`](../scope.nix) |
| [`deps.nix`](deps.nix) | `libyang`, `sysrepo`, `faux`, `klish` | [`../deps/`](../deps/) |
| [`build.nix`](build.nix) | the C components and variants, the Go modules, `compile-db`; checks `build-*`, `go-test-*` | [`../build/`](../build/) |
| [`analysis.nix`](analysis.nix) | `analysis-quick`, `-standard`, `-deep`, `analysis-<tool>`; checks `analysis-quick`, `triage-test` | [`../analysis/`](../analysis/) |
| [`fuzz.nix`](fuzz.nix) | `fuzz`, `fuzz-run`, `fuzz-cov`, `fuzz-selftest`, `fuzz-go-src`, `fuzz-go-run`; apps `fuzz-deep`, `fuzz-go`; check `fuzz-selftest` | [`../fuzz/`](../fuzz/) |
| [`report.nix`](report.nix) | `analysis-report`: the deep tier plus the fuzz runs, ranked by triage | [`../analysis/default.nix`](../analysis/default.nix) `mkReport` |
| [`apps.nix`](apps.nix) | apps `vulncheck`, `secrets-scan`, `deps-drift`; check `deps-drift` | [`../apps/`](../apps/) |
| [`dev.nix`](dev.nix) | `devShells.default`, `devShells.buildroot`, app `buildroot`, `formatter` | [`../dev/`](../dev/) |

To add an area: write its code under `nix/<area>/` returning `{ packages, checks, apps }`,
add it to `../scope.nix` with `self.callPackage`, then add a part here that inherits
those attributes, and list the part in `flake.nix`'s `imports`.
