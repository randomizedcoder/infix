# nix/analysis/cppcheck.nix
#
# cppcheck over the compile DB (../build/compile-db.nix), so it sees each file's
# real defines and include paths.  `exhaustive = true` is the deep-tier variant:
# every check enabled and --check-level=exhaustive.

{ mkAnalysisTool, versions, lib, exhaustive ? false }:

mkAnalysisTool {
  name = "cppcheck${lib.optionalString exhaustive "-exhaustive"}";
  cdb = true;
  tools = [ versions.cppcheck ];
  script = ''
    args=(
      --project=compile_commands.json
      --enable=${if exhaustive then "all" else "warning,performance,portability"}
      ${lib.optionalString exhaustive "--check-level=exhaustive"}
      # The code is built with GCC; libite's strdupa.h has an #error for other compilers.
      -D__GNUC__=14
      --library=gnu
      --suppress=missingIncludeSystem
      "--suppress=*:/nix/store/*"
      --suppress=checkersReport
      ${lib.optionalString exhaustive "--suppress=unusedFunction"}
      --inline-suppr
      --quiet
      -j "$NIX_BUILD_CORES"
      --cppcheck-build-dir="$TMPDIR"
    )
    cppcheck "''${args[@]}" --template='{file}:{line}:{column}: {severity}: {message} [{id}]' \
      2> "$out/report.txt" || true
    cppcheck "''${args[@]}" --xml 2> "$out/report.xml" || true
  '';
  count = "^[^:]+:[0-9]+:[0-9]+: (error|warning|style|performance|portability|information):";
}
