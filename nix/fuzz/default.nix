# nix/fuzz/default.nix
#
# libFuzzer harnesses for the C parsers (the HomaModule pattern).  Each harness
# #includes the .c file it tests, compiled with that file's flags from the
# compile DB (../build/compile-db.nix), so static functions are reachable and
# src/ is not changed.
#
#   fuzz           the harnesses (ASan + UBSan) and bin/run-fuzzers
#                  (FUZZ_TIME=300 ./result/bin/run-fuzzers [outdir])
#   fuzz-run       a 20 s run of each -> summary.txt, count.txt, report.txt, crashes/
#   fuzz-deep      nix run .#fuzz-deep -- [outdir]: fork mode and the dictionaries,
#                  FUZZ_DEEP_TIME seconds per harness
#   fuzz-cov       llvm-cov of the code the harnesses reach, over a 20 s run each
#   fuzz-selftest  fails unless the toolchain catches a planted overflow
#
# The Go fuzz targets are in go.nix.  fuzz, fuzz-run and fuzz-deep run the
# harnesses through tools/run-fuzzers.sh, which also sorts the crashes by
# sanitizer signature.

{ pkgs
, lib
, versions
, compileDb
, cPkgs
, goPkgs
, infixLib
}:

let
  src = lib.fileset.toSource { root = ./.; fileset = ./.; };
  inherit (versions) llvm;
  sanFlags = "-g -O1 -fno-omit-frame-pointer -fsanitize=fuzzer,address,undefined";
  symbolizer = "${lib.getBin llvm.llvm}/bin/llvm-symbolizer";

  # Harness name (harness/c/fuzz_<name>.c) -> the file under src/ it includes.
  harnesses = {
    selftest = null;
    yangerd_frame = "statd/yangerd.c";
    statd_paths = "statd/statd.c";
    journal_name = "statd/journal_retention.c";
    syslog_escape = "confd/src/syslog.c";
    netd_config = "netd/src/config.c";
    srx_fgetkey = "libsrx/src/helpers.c";
    base64 = "confd/src/base64.c";
  };

  # Every library a target may call.  What else the included file refers to
  # (functions in the component's other files) gets a stub that traps; the
  # harness never reaches it.
  libs = "-lsrx -lyang -lsysrepo -ljansson -lite -lconfuse -lev -lz";

  # infix-fuzz <bindir> <corpus> [outdir]: see tools/run-fuzzers.sh.
  runner = pkgs.writeShellApplication {
    name = "infix-fuzz";
    runtimeInputs = with pkgs; [ coreutils findutils gawk gnugrep gnused ];
    runtimeEnv.ASAN_SYMBOLIZER_PATH = symbolizer;
    text = builtins.readFile ./tools/run-fuzzers.sh;
  };

  # A command for a build's bin/: runs the harnesses installed next to it,
  # seeded from the build's corpus/; "$@" is the outdir.
  launcher = name: pkgs.writeShellApplication {
    inherit name;
    text = ''
      here=$(dirname "$(readlink -f "$0")")
      exec ${lib.getExe runner} "$here" "$here/../corpus" "$@"
    '';
  };

  # A derivation that compiles harnesses: the configured C components in
  # ./src, their compile DB, clang, and the libraries they link.  It defines
  # build_harness <name> <out> [flags...].
  mkFuzzDrv = args: llvm.stdenv.mkDerivation ({
    inherit (infixLib) version;
    dontUnpack = true;
    hardeningDisable = [ "all" ];
    dontConfigure = true;
    dontInstall = true;
    dontFixup = true;
    buildInputs = lib.unique (lib.concatMap (c: cPkgs.components.${c}.inputs) [ "confd" "statd" "netd" ])
      ++ [ cPkgs.byVariant.release.libsrx ];
    preBuild = ''
      ${compileDb.setup}
      declare -gA target=(${lib.concatStrings (lib.mapAttrsToList (n: t:
        lib.optionalString (t != null) "[${n}]=${t} ") harnesses)})
      build_harness() {
        local name=$1 out=$2 t flags=()
        shift 2
        t=''${target[$name]:-}
        if [ -n "$t" ]; then
          mapfile -t flags < <(python3 ${./tools/db-flags.py} compile_commands.json "src/$t")
          flags+=(-I "src/$(dirname "$t")")
        fi
        echo "fuzz_$name: ''${t:-standalone}"
        clang ${sanFlags} "''${flags[@]}" "$@" -I ${src}/harness/c \
          -c ${src}/harness/c/fuzz_$name.c -o "$name.o"
        : > "$name-stubs.c"
        if ! clang ${sanFlags} "$@" "$name.o" -o "$out" ${libs} 2> "$name-link.log"; then
          sed -nE 's/.*undefined reference to .([A-Za-z_][A-Za-z0-9_]*).*/\1/p' "$name-link.log" | sort -u |
            sed 's/.*/void &(void) { __builtin_trap(); }/' > "$name-stubs.c"
          echo "fuzz_$name: $(wc -l < "$name-stubs.c") stub(s)"
          clang ${sanFlags} "$@" "$name.o" "$name-stubs.c" -o "$out" ${libs}
        fi
      }
    '';
  } // args // {
    nativeBuildInputs = [ pkgs.python3 ] ++ args.nativeBuildInputs or [ ];
  });

  names = lib.attrNames harnesses;

  fuzz = mkFuzzDrv {
    pname = "infix-fuzzers";
    buildPhase = ''
      runHook preBuild
      mkdir -p "$out/bin" "$out/corpus" "$out/dict"
      ${lib.concatMapStrings (n: ''
        build_harness ${n} "$out/bin/fuzz_${n}"
        mkdir -p "$out/corpus/fuzz_${n}"
        cp ${src}/corpus-seeds/${n}/* "$out/corpus/fuzz_${n}/" 2>/dev/null || true
      '') names}
      cp ${src}/dict/* "$out/dict/"
      cp ${launcher "run-fuzzers"}/bin/run-fuzzers "$out/bin/"
      runHook postBuild
    '';
  };

  fuzz-run = pkgs.runCommand "infix-fuzz-run" { } ''
    FUZZ_TIME=20 ${lib.getExe runner} ${fuzz}/bin ${fuzz}/corpus "$out"
  '';

  # A command, not a build, so that its time limit can be set when it runs.
  fuzz-deep = pkgs.writeShellApplication {
    name = "fuzz-deep";
    text = ''
      # fuzz-deep [outdir]: FUZZ_DEEP_TIME (60 s per harness), FUZZ_DEEP_FORKS (2),
      # FUZZ_DEEP_MAXLEN (4096).
      export FUZZ_TIME=''${FUZZ_DEEP_TIME:-60} FUZZ_FORKS=''${FUZZ_DEEP_FORKS:-2} \
        FUZZ_MAXLEN=''${FUZZ_DEEP_MAXLEN:-4096}
      exec ${lib.getExe runner} ${fuzz}/bin ${fuzz}/corpus "''${1:-fuzz-deep-out}"
    '';
  };

  # Coverage of the functions each harness reaches in 20 s from its seeds
  # (those with any region run).
  fuzz-cov = mkFuzzDrv {
    pname = "infix-fuzz-cov";
    nativeBuildInputs = [ llvm.llvm ];
    buildPhase = ''
      runHook preBuild
      mkdir -p "$out" bin
      ${lib.concatMapStrings (n: lib.optionalString (harnesses.${n} != null) ''
        build_harness ${n} bin/fuzz_${n} -fprofile-instr-generate -fcoverage-mapping
        mkdir -p corpus/${n}
        cp ${src}/corpus-seeds/${n}/* corpus/${n}/ 2>/dev/null || true
        LLVM_PROFILE_FILE="$PWD/${n}.profraw" ASAN_OPTIONS=detect_leaks=0 \
          bin/fuzz_${n} -max_total_time=20 corpus/${n} > "$out/${n}.log" 2>&1 || true
        llvm-profdata merge -sparse ${n}.profraw -o ${n}.profdata
        {
          echo "== fuzz_${n} (src/${harnesses.${n}})"
          llvm-cov report --show-functions bin/fuzz_${n} -instr-profile=${n}.profdata "src/${harnesses.${n}}" 2>&1 |
            awk 'NR <= 2 || $3 != $2'
        } >> "$out/summary.txt"
      '') names}
      cat "$out/summary.txt"
      runHook postBuild
    '';
  };

  # The planted bug: SELFTEST_COPY_LEN=32 into an 8-byte buffer must abort under ASan.
  fuzz-selftest = mkFuzzDrv {
    pname = "infix-fuzz-selftest";
    buildPhase = ''
      runHook preBuild
      mkdir -p "$out"
      build_harness selftest selftest_broken -DSELFTEST_COPY_LEN=32
      head -c 32 /dev/zero | tr '\0' 'A' > overflow.bin
      rc=0
      ./selftest_broken overflow.bin > "$out/selftest.log" 2>&1 || rc=$?
      if [ "$rc" -ne 0 ] && grep -q 'AddressSanitizer: heap-buffer-overflow' "$out/selftest.log"; then
        echo "SELFTEST PASS: the planted overflow was caught (rc=$rc)" | tee "$out/verdict.txt"
      else
        echo "SELFTEST FAILED: the planted overflow was not caught (rc=$rc)" >&2
        cat "$out/selftest.log" >&2
        exit 1
      fi
      runHook postBuild
    '';
  };

  go = import ./go.nix { inherit pkgs lib versions goPkgs src; };
in
{
  packages = { inherit fuzz fuzz-run fuzz-deep fuzz-cov fuzz-selftest; } // go.packages;
  checks = { inherit fuzz-selftest; };
  # Commands for `nix run`, so their time limits can be set when they run.
  apps = { inherit fuzz-deep; inherit (go.packages) fuzz-go; };
}
