# nix/analysis/ruff.nix
#
# ruff over every tracked Python file: pyflakes (F), syntax errors (E9), bugbear
# (B), pylint errors (PLE) and the bandit-derived security rules (S), without
# S101 (assert, which the tests use on purpose).

{ mkAnalysisTool, versions }:

mkAnalysisTool {
  name = "ruff";
  tools = [ versions.ruff ];
  script = ''
    export RUFF_CACHE_DIR=$TMPDIR/ruff
    ruff check --no-respect-gitignore --isolated --select F,E9,B,PLE,S --ignore S101 \
      --exclude patches --output-format concise . > "$out/report.txt" 2>&1 || true
    ruff check --no-respect-gitignore --isolated --select F,E9,B,PLE,S --ignore S101 \
      --exclude patches --output-format json . > "$out/report.json" 2>/dev/null || true
  '';
  count = "^[^ ]+:[0-9]+:[0-9]+: ";
}
