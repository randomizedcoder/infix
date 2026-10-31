# nix/parts/report.nix
#
# analysis-report: the deep tier and the 20 s fuzz runs, every finding scored and
# ranked by ../analysis/triage -> findings.json, top.txt, triage.md.

{
  perSystem = { infix, pkgs, ... }: {
    packages.analysis-report = infix.analysisPkgs.mkReport {
      extraDirs = [
        (pkgs.linkFarm "infix-fuzz-reports" {
          fuzz = infix.fuzzPkgs.packages.fuzz-run;
          go-fuzz = infix.fuzzPkgs.packages.fuzz-go-run;
        })
      ];
    };
  };
}
