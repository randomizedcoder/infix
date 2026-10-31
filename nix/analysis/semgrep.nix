# nix/analysis/semgrep.nix
#
# semgrep with the local rules in semgrep-rules.yaml (C, Go, Python), offline.

{ mkAnalysisTool, versions, jq, cacert }:

mkAnalysisTool {
  name = "semgrep";
  tools = [ versions.semgrep ];
  script = ''
    # semgrep-core sets up its telemetry client, which needs a CA bundle, even offline.
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    export HOME=$TMPDIR SEMGREP_ENABLE_VERSION_CHECK=0 SEMGREP_SEND_METRICS=off OTEL_TRACES_EXPORTER=none
    targets=(src test board utils)
    semgrep scan --config ${./semgrep-rules.yaml} --metrics=off --disable-version-check \
      --timeout 600 --timeout-threshold 0 --no-git-ignore --exclude vendor --exclude patches -j "$NIX_BUILD_CORES" \
      --json --output "$out/report.json" "''${targets[@]}" > semgrep.log 2>&1 || true
    [ -s "$out/report.json" ] || { tail -40 semgrep.log; exit 1; }
    ${jq}/bin/jq -r '.results[] | "\(.path):\(.start.line):\(.start.col): \(.extra.severity | ascii_downcase): \(.extra.message | gsub("\\s+"; " ")) [\(.check_id | sub(".*\\."; ""))]"' \
      "$out/report.json" | sort > "$out/report.txt"
    ${jq}/bin/jq -r '.errors[]? | "semgrep error: \(.message // .type)"' "$out/report.json" | head -50 > "$out/errors.txt"
  '';
  count = ":[0-9]+:[0-9]+: (error|warning|info):";
}
