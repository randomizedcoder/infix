# nix/analysis/bandit.nix
#
# bandit over the tracked Python (test framework, board scripts, utils).

{ mkAnalysisTool, versions }:

mkAnalysisTool {
  name = "bandit";
  tools = [ versions.bandit ];
  script = ''
    bandit -q -r . -x ./patches,./buildroot -f custom \
      --msg-template '{relpath}:{line}: {severity}: {test_id}: {msg}' > "$out/report.txt" 2>/dev/null || true
    bandit -q -r . -x ./patches,./buildroot -f json > "$out/report.json" 2>/dev/null || true
    sed -i 's|^\./||' "$out/report.txt"
  '';
  count = "^[^:]+:[0-9]+: (LOW|MEDIUM|HIGH):";
}
