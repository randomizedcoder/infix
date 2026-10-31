# nix/analysis/nix-lint.nix
#
# nixpkgs-fmt --check, statix and deadnix over flake.nix and nix/.

{ mkAnalysisTool, versions, jq }:

mkAnalysisTool {
  name = "nix-lint";
  tools = [ versions.nixpkgs-fmt versions.statix versions.deadnix jq ];
  script = ''
    {
      echo "# nixpkgs-fmt"
      nixpkgs-fmt --check flake.nix nix 2>&1 | sed -n 's|^\(.*\.nix\)$|\1: not nixpkgs-fmt formatted|p' || true
      echo "# statix"
      # errfmt is "file>line:col:W:code:message"
      { statix check -o errfmt flake.nix 2>&1 || true; statix check -o errfmt nix 2>&1 || true; } |
        sed -E 's/^(.*\.nix)>([0-9]+):([0-9]+):([A-Z]):([0-9]+):(.*)$/\1:\2:\3: warning: \6 [statix-\4\5]/'
      echo "# deadnix"
      deadnix -o json flake.nix nix 2>/dev/null \
        | jq -r '.file as $f | .results[] | "\($f):\(.line):\(.column): unused: \(.message)"' || true
    } > "$out/report.txt"
  '';
  count = "\\.nix(:[0-9]+:[0-9]+)?: ";
}
