# nix/analysis/clang-format.nix
#
# clang-format --dry-run against src/.clang-format over the C components: one
# finding per line that would be reformatted.
#
# src/.clang-format sets ColumnLimit twice, meaning the override at the end to
# win; clang-format 21 rejects duplicate keys, so the check reports that and
# runs on a copy with only the last of each top-level key.

{ mkAnalysisTool, infixLib, versions, python3 }:

mkAnalysisTool {
  name = "clang-format";
  src = infixLib.src.c;
  tools = [ versions.llvm.clang-tools python3 ];
  script = ''
    python3 - src/.clang-format > clang-format.yml 2> "$out/report.txt" <<'PY'
    import re, sys
    # Top-level blocks: a "Key:" line and the indented or list lines under it.
    blocks, seen = [], {}
    for n, line in enumerate(open(sys.argv[1]), 1):
        m = re.match(r"([A-Za-z]+):", line)
        if m or not blocks:
            key = m.group(1) if m else None
            if key in seen:
                print(f"src/.clang-format:{n}:1: warning: duplicated key {key}, "
                      "rejected by clang-format 21 [duplicate-key]", file=sys.stderr)
                blocks[seen[key]][1].clear()
            if key:
                seen[key] = len(blocks)
            blocks.append((key, []))
        blocks[-1][1].append(line)
    sys.stdout.write("".join(line for _, lines in blocks for line in lines))
    PY
    find src -name '*.[ch]' -not -path '*/vendor/*' | sort | while read -r f; do
      clang-format --style=file:clang-format.yml --dry-run "$f" 2>&1 || true
    done >> "$out/report.txt"
  '';
  count = ": warning: (code should be clang-formatted|duplicated key)";
}
