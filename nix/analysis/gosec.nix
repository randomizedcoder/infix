# nix/analysis/gosec.nix
#
# gosec in every Go module, as SARIF (for code-scanning tools) and as text
# lines made from the SARIF.  Test files are left out, as gosec does by default.

{ mkAnalysisTool, versions, infixLib, jq }:

mkAnalysisTool {
  name = "gosec";
  go = true;
  tools = [ versions.gosec jq ];
  script = ''
    goEach sh -c '
      gosec -quiet -exclude-dir=vendor -fmt sarif -out "$0/$(basename "$PWD").sarif" ./... >/dev/null 2>&1 || true
    ' "$out"
    # "src/<module>/path.go:12:3: error: G204: message"
    for m in ${toString infixLib.goModules}; do
      [ -f "$out/$m.sarif" ] || continue
      jq -r --arg m "$m" '.runs[].results[] |
        .locations[0].physicalLocation as $l |
        "src/\($m)/\($l.artifactLocation.uri):\($l.region.startLine):\($l.region.startColumn): \(.level): \(.ruleId): \(.message.text | gsub("\\s+"; " "))"' \
        "$out/$m.sarif"
    done | sort > "$out/report.txt"
  '';
  count = "^src/[^:]+:[0-9]+:[0-9]+: [a-z]+: G[0-9]+:";
}
