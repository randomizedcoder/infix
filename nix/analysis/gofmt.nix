# nix/analysis/gofmt.nix
#
# gofmt -l on every Go module: one finding per file that is not gofmt-clean.

{ mkAnalysisTool }:

mkAnalysisTool {
  name = "gofmt";
  go = true;
  script = ''
    goEach sh -c 'gofmt -l $(find . -name "*.go" -not -path "./vendor/*") | sed "s|^\./|src/$(basename $PWD)/|"' \
      > "$out/report.txt" 2>&1
  '';
  count = "\\.go$";
}
