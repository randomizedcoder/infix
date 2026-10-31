# nix/analysis/go-vet.nix
#
# go vet ./... in every Go module.

{ mkAnalysisTool }:

mkAnalysisTool {
  name = "go-vet";
  go = true;
  script = ''
    goEach sh -c 'echo "# $(basename $PWD)"; go vet ./... 2>&1 | sed "s|^\./|src/$(basename $PWD)/|"' \
      > "$out/report.txt" 2>&1 || true
  '';
  count = "^src/[^:]+:[0-9]+:[0-9]+: ";
}
