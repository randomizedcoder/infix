# nix/parts/analysis.nix
#
# The static analysis tiers and tools (../analysis): analysis-quick, -standard,
# -deep and analysis-<tool>.
# analysis-quick and the triage unit tests are `nix flake check`s.

{
  perSystem = { infix, ... }: {
    inherit (infix.analysisPkgs) packages checks;
  };
}
