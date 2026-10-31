# nix/analysis/go-race.nix
#
# go test -race in every module (../build/go.nix); the finding count is failed
# tests and data races.  A failing module fails the build of go-test, and with it
# this report, so a race is never a silent zero.

{ mkAnalysisTool, goPkgs, infixLib, lib }:

mkAnalysisTool {
  name = "go-race";
  src = null;
  script = ''
    ${lib.concatMapStrings (m: ''
      echo "# ${m}"
      cat ${goPkgs.packages."go-test-${m}"}/report.txt
    '') infixLib.goModules} > "$out/report.txt"
  '';
  count = "^(--- FAIL|WARNING: DATA RACE)";
}
