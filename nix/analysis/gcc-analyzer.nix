# nix/analysis/gcc-analyzer.nix
#
# gcc -fanalyzer: GCC's interprocedural analysis (double free, use after free,
# leaks, NULL dereference, tainted array index, fd leaks), re-running each
# compile command in the compile DB with -fanalyzer and without -Werror.

{ mkAnalysisTool, python3 }:

mkAnalysisTool {
  name = "gcc-analyzer";
  cdb = true;
  tools = [ python3 ];
  script = ''
    python3 ${./gcc-analyzer.py} compile_commands.json "$NIX_BUILD_CORES" > "$out/report.txt"
  '';
  count = ":[0-9]+:[0-9]+: warning: .*\\[-Wanalyzer-";
}
