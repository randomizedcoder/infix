# nix/analysis/shellcheck.nix
#
# shellcheck over every tracked shell script: *.sh and files with a sh or bash
# shebang, outside vendor/ and patches/.

{ mkAnalysisTool, versions }:

mkAnalysisTool {
  name = "shellcheck";
  tools = [ versions.shellcheck ];
  script = ''
    find . -type f -not -path './patches/*' -not -path '*/vendor/*' -not -path './.git/*' \
      \( -name '*.sh' -o -exec sh -c 'head -c 64 "$1" | grep -qE "^#!.*(/|env )(ba)?sh\b"' _ {} \; \) \
      -print | sort > scripts.txt
    echo "# shellcheck over $(wc -l < scripts.txt) scripts" > "$out/report.txt"
    xargs -a scripts.txt shellcheck --format=gcc -x >> "$out/report.txt" 2>&1 || true
    sed -i 's|^\./||' "$out/report.txt"
  '';
  count = ":[0-9]+:[0-9]+: (error|warning|note):";
}
