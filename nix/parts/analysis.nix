# nix/parts/analysis.nix
#
# The static analysis tiers and tools (../analysis): analysis-quick, -standard,
# -deep, analysis-<tool> and analysis-report (triage over the deep tier).
# analysis-quick and the triage unit tests are `nix flake check`s.

{
  perSystem = { infix, ... }: {
    inherit (infix.analysisPkgs) packages checks;
  };
}
