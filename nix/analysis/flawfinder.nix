# nix/analysis/flawfinder.nix
#
# flawfinder over the C components: risky libc calls (system, sprintf, strcpy,
# fixed buffers), ranked 0-5.  Level 2 and up.

{ mkAnalysisTool, infixLib, versions }:

mkAnalysisTool {
  name = "flawfinder";
  src = infixLib.src.c;
  tools = [ versions.flawfinder ];
  script = ''
    flawfinder --minlevel=2 --columns --singleline --dataonly --quiet src > "$out/report.txt" 2>&1 || true
    flawfinder --minlevel=2 --sarif src > "$out/report.sarif" 2>/dev/null || true
  '';
  count = "^[^:]+:[0-9]+:[0-9]+: +\\[[0-9]\\]";
}
