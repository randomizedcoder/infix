# nix/analysis/yanglint.nix
#
# yanglint (from the pinned libyang) over every module in src/confd/yang/confd,
# loaded together so references between modules resolve.  Submodules come in
# through their main module.

{ mkAnalysisTool, infixLib, libyang }:

mkAnalysisTool {
  name = "yanglint";
  src = infixLib.src.yang;
  tools = [ libyang ];
  script = ''
    cd src/confd/yang/confd
    mapfile -t mods < <(grep -L '^submodule ' -- *.yang)
    echo "# yanglint over ''${#mods[@]} modules" > "$out/report.txt"
    yanglint -p . "''${mods[@]}" >> "$out/report.txt" 2>&1 || true
  '';
  count = "libyang (err|warn)";
}
