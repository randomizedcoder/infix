# nix/analysis/codechecker.nix
#
# The clang static analyzer through CodeChecker, with cross translation unit
# analysis, so a NULL or a tainted length is followed from libsrx into confd.

{ mkAnalysisTool, versions, unzip }:

mkAnalysisTool {
  name = "codechecker";
  cdb = true;
  tools = [ versions.codechecker versions.llvm.clang versions.llvm.clang-tools ];
  script = ''
    export HOME=$TMPDIR
    # CodeChecker looks for clang-extdef-mapping (CTU) next to the clang it runs.
    mkdir -p "$TMPDIR/ccbin"
    # It resolves symlinks, so clang is a script.
    printf '#!%s\nexec %s "$@"\n' "$BASH" ${versions.llvm.clang}/bin/clang > "$TMPDIR/ccbin/clang"
    chmod +x "$TMPDIR/ccbin/clang"
    ln -s ${versions.llvm.clang-tools}/bin/clang-extdef-mapping "$TMPDIR/ccbin/"
    export PATH=$TMPDIR/ccbin:$PATH
    CodeChecker analyze compile_commands.json --analyzers clangsa --ctu \
      --enable sensitive -j "$NIX_BUILD_CORES" -o reports > analyze.log 2>&1 || true
    tail -20 analyze.log > "$out/analyze.log"
    # The first error of each translation unit clang could not analyze.
    for z in reports/failed/*.zip; do
      [ -f "$z" ] || continue
      echo "== $(basename "$z" .zip)"
      ${unzip}/bin/unzip -p "$z" stderr | grep -m3 -E 'error|fatal' || true
    done > "$out/failed.txt"
    CodeChecker parse reports --trim-path-prefix "$PWD/" > parse.txt 2>&1 || true
    CodeChecker parse reports -e json -o "$out/report.json" --trim-path-prefix "$PWD/" >/dev/null 2>&1 || true
    # "[HIGH] src/confd/x.c:12:3: message [checker]"
    grep -E '^\[(CRITICAL|HIGH|MEDIUM|LOW|STYLE|UNSPECIFIED)\] ' parse.txt | sort -u > "$out/report.txt" || true
  '';
  count = "^\\[(CRITICAL|HIGH|MEDIUM|LOW|STYLE|UNSPECIFIED)\\] ";
}
