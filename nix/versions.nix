# nix/versions.nix
#
# The toolchains and tools every other file uses, in one place.  Changing one here
# changes the dev shell, the builds and the checks together.

{ pkgs }:

{
  # yangerd's go.mod needs Go 1.26.
  go = pkgs.go_1_26;
  buildGoModule = pkgs.buildGo126Module;

  # clang, libFuzzer, clang-tidy and the static analyzer all come from one LLVM.
  llvm = pkgs.llvmPackages_21;

  inherit (pkgs)
    cppcheck
    flawfinder
    semgrep
    codechecker
    bear
    golangci-lint
    gosec
    govulncheck
    osv-scanner
    gitleaks
    shellcheck
    ruff
    bandit
    nixpkgs-fmt
    statix
    deadnix
    ;
  staticcheck = pkgs.go-tools;
}
