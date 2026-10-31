# nix/analysis/default.nix
#
# Tiered static analysis (the HomaModule and xdp2 pattern).  Each tool is one
# mkAnalysisTool call in its own file, writing $out/report.txt (plus report.json,
# .xml or .sarif where the tool has one) and $out/count.txt; a tier gathers the
# reports of its tools into one directory with a summary.txt.
#
#   analysis-quick     formatters and linters: clang-format, shellcheck, ruff, gofmt,
#                      go vet, yanglint, and nixpkgs-fmt/statix/deadnix on nix/
#   analysis-standard  + cppcheck, clang-tidy, flawfinder, bandit, golangci-lint, gosec
#   analysis-deep      + CodeChecker (clang static analyzer, cross-TU), gcc -fanalyzer,
#                      cppcheck exhaustive, semgrep (semgrep-rules.yaml), golangci
#                      comprehensive, go test -race
#
# Every tool is also its own package, analysis-<tool>.  Report paths are relative
# to the repository root (src/confd/system.c), which is what triage/ reads.

{ pkgs
, lib
, infixLib
, versions
, compileDb
, goPkgs
, cPkgs
, libyang
}:

let
  # mkAnalysisTool { name, tools, script, count, src?, cdb?, go? }
  #   src    a source tree copied to ./ first (default: the tracked tree; null: none)
  #   cdb    true: the configured C components in ./src and ./compile_commands.json
  #          (../build/compile-db.nix) instead of src
  #   go     true: every Go module with its vendor/ in ./src, and Go set up offline
  #   count  extended regex; report.txt lines that match are the finding count
  mkAnalysisTool = { name, tools ? [ ], script, count, src ? infixLib.src.all, cdb ? false, go ? false }:
    pkgs.runCommandCC "infix-analysis-${name}"
      { nativeBuildInputs = tools ++ lib.optional go versions.go; }
      ''
        mkdir work && cd work
        ${if cdb then compileDb.setup
          else if go then goSetup
          else lib.optionalString (src != null) "cp -r --no-preserve=mode ${src}/. ."}
        mkdir -p "$out"
        ${script}
        for f in "$out"/report.*; do
          [ -f "$f" ] && sed -i "s|$PWD/||g" "$f"
        done
        count=$(grep -cE '${count}' "$out/report.txt" || true)
        echo "''${count:-0}" > "$out/count.txt"
      '';

  # The vendored sources of every module, merged; they share src/features.
  goSetup = ''
    mkdir -p src
    ${lib.concatMapStrings (m: ''
      cp -r --no-preserve=mode ${goPkgs.goMods.${m}.vendoredSource}/. src/
    '') infixLib.goModules}
    export HOME=$TMPDIR GOCACHE=$TMPDIR/go-cache GOPATH=$TMPDIR/go
    export GOTOOLCHAIN=local GOPROXY=off GOFLAGS=-mod=mod CGO_ENABLED=0
    # goEach <cmd...>: runs cmd in src/<module>, vendored where there is a vendor/.
    goEach() {
      local m
      for m in ${toString infixLib.goModules}; do
        (cd "src/$m" && { [ -d vendor ] && export GOFLAGS=-mod=vendor; "$@"; })
      done
    }
  '';

  call = lib.callPackageWith (pkgs // {
    inherit infixLib versions compileDb goPkgs cPkgs libyang mkAnalysisTool;
  });

  tools = {
    # quick
    clang-format = call ./clang-format.nix { };
    shellcheck = call ./shellcheck.nix { };
    ruff = call ./ruff.nix { };
    gofmt = call ./gofmt.nix { };
    go-vet = call ./go-vet.nix { };
    yanglint = call ./yanglint.nix { };
    nix-lint = call ./nix-lint.nix { };
    # standard
    # Passed explicitly: callPackage would fill it from pkgs.exhaustive, a Go linter.
    cppcheck = call ./cppcheck.nix { exhaustive = false; };
    clang-tidy = call ./clang-tidy.nix { };
    flawfinder = call ./flawfinder.nix { };
    bandit = call ./bandit.nix { };
    golangci-lint = call ./golangci-lint.nix { tier = "standard"; };
    gosec = call ./gosec.nix { };
    # deep
    codechecker = call ./codechecker.nix { };
    gcc-analyzer = call ./gcc-analyzer.nix { };
    cppcheck-exhaustive = call ./cppcheck.nix { exhaustive = true; };
    semgrep = call ./semgrep.nix { };
    golangci-lint-comprehensive = call ./golangci-lint.nix { tier = "comprehensive"; };
    go-race = call ./go-race.nix { };
  };

  quick = [ "clang-format" "shellcheck" "ruff" "gofmt" "go-vet" "yanglint" "nix-lint" ];
  standard = quick ++ [ "cppcheck" "clang-tidy" "flawfinder" "bandit" "golangci-lint" "gosec" ];
  deep = standard ++ [
    "codechecker"
    "gcc-analyzer"
    "cppcheck-exhaustive"
    "semgrep"
    "golangci-lint-comprehensive"
    "go-race"
  ];

  # A tier: every tool's output under <tool>/, and summary.txt with the counts.
  mkTier = tierName: names: pkgs.runCommand "infix-${tierName}" { } ''
    mkdir -p "$out"
    total=0
    echo "=== Infix ${tierName} ===" > "$out/summary.txt"
    ${lib.concatMapStrings (n: ''
      cp -r ${tools.${n}} "$out/${n}"
      c=$(cat "$out/${n}/count.txt")
      printf '  %-28s %s finding(s)\n' "${n}:" "$c" >> "$out/summary.txt"
      total=$((total + c))
    '') names}
    echo "" >> "$out/summary.txt"
    echo "Total: $total finding(s)" >> "$out/summary.txt"
    echo "$total" > "$out/count.txt"
    cat "$out/summary.txt"
  '';

  tiers = {
    analysis-quick = mkTier "analysis-quick" quick;
    analysis-standard = mkTier "analysis-standard" standard;
    analysis-deep = mkTier "analysis-deep" deep;
  };

  # triage/ ranks the findings of a tier: findings.json, top.txt, triage.md.
  triage = lib.fileset.toSource {
    root = ./.;
    fileset = ./triage;
  };

  # analysis-report: the deep tier with every finding scored and ranked.
  # extraDirs adds more <tool>/report.txt directories (the fuzz runs).
  mkReport = { extraDirs ? [ ] }: pkgs.runCommand "infix-analysis-report"
    { nativeBuildInputs = [ pkgs.python3 ]; }
    ''
      mkdir -p "$out"
      cp -r --no-preserve=mode ${tiers.analysis-deep}/. "$out/"
      ${lib.concatMapStrings (d: "cp -rL --no-preserve=mode ${d}/. \"$out/\"\n") extraDirs}
      python3 ${triage}/triage "$out" --output-dir "$out"
      head -40 "$out/top.txt"
    '';

  triage-test = pkgs.runCommand "infix-triage-test"
    { nativeBuildInputs = [ pkgs.python3 ]; }
    ''
      cd ${triage}
      python3 -m unittest discover -s triage -p 'test_*.py' -v 2>&1 | tee "$out"
    '';
in
{
  inherit tools tiers mkAnalysisTool mkReport;

  # analysis-report is ../parts/report.nix: it adds the fuzz runs.
  packages = tiers // lib.mapAttrs' (n: v: lib.nameValuePair "analysis-${n}" v) tools;
  checks = { inherit (tiers) analysis-quick; inherit triage-test; };
}
