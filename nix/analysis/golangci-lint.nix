# nix/analysis/golangci-lint.nix
#
# golangci-lint in every Go module, at one of the tiers in go/:
#   quick          golangci-quick.yml           (dev shell only)
#   standard       golangci.yml                 (analysis-standard)
#   comprehensive  golangci-comprehensive.yml   (analysis-deep)
# The timeout comes from the config; a --timeout here would override it.

{ mkAnalysisTool, versions, lib, tier ? "standard" }:

let
  config = {
    quick = ./go/golangci-quick.yml;
    standard = ./go/golangci.yml;
    comprehensive = ./go/golangci-comprehensive.yml;
  }.${tier};
in
mkAnalysisTool {
  name = "golangci-lint${lib.optionalString (tier != "standard") "-${tier}"}";
  go = true;
  tools = [ versions.golangci-lint ];
  script = ''
    export GOLANGCI_LINT_CACHE=$TMPDIR/golangci
    goEach sh -c '
      m=$(basename "$PWD")
      golangci-lint run --config ${config} --path-mode=abs \
        --output.text.path=stdout --output.text.print-issued-lines=false \
        --output.json.path="$0/$m.json" ./... 2>&1 | grep -E "^/" || true
    ' "$out" > "$out/report.txt"
  '';
  count = "^src/[^:]+:[0-9]+(:[0-9]+)?: ";
}
