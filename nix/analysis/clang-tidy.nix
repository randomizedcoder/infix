# nix/analysis/clang-tidy.nix
#
# clang-tidy over the compile DB, with the bug-finding and security checks on and
# the style-only ones off.  The tree has no .clang-tidy, so the list is here.

{ mkAnalysisTool, versions, lib }:

let
  checks = lib.concatStringsSep "," [
    "-*"
    "bugprone-*"
    "cert-*"
    "clang-analyzer-*"
    "concurrency-*"
    "misc-*"
    "performance-*"
    "portability-*"
    # Style, or noise in C with these APIs.
    "-bugprone-easily-swappable-parameters"
    "-bugprone-assignment-in-if-condition"
    "-bugprone-reserved-identifier"
    "-cert-dcl37-c"
    "-cert-dcl51-cpp"
    "-misc-include-cleaner"
    "-misc-no-recursion"
    "-clang-analyzer-security.insecureAPI.DeprecatedOrUnsafeBufferHandling"
  ];
in
mkAnalysisTool {
  name = "clang-tidy";
  cdb = true;
  tools = [ versions.llvm.clang-tools ];
  script = ''
    # gcc-only flags in the DB make clang-tidy stop with an error.
    run-clang-tidy -quiet -j "$NIX_BUILD_CORES" -p . -checks='${checks}' \
      -extra-arg=-Wno-unknown-warning-option -extra-arg=-Wno-error \
      'src/.*\.c$' 2>/dev/null \
      | grep -E '^[^ ]+:[0-9]+:[0-9]+: (warning|error):' | sort -u > "$out/report.txt" || true
  '';
  count = ":[0-9]+:[0-9]+: (warning|error):";
}
