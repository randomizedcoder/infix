# nix/fuzz/go.nix
#
# Go native fuzzing.  harness/go/<module>/<package>/fuzz_test.go is copied into
# the module's vendored source (so src/ is not changed) and every Fuzz function
# in it runs with `go test -fuzz`, offline.
#
#   fuzz-go-src  the modules with the fuzz tests in place
#   fuzz-go-run  each target for 10 s -> summary.txt, count.txt, report.txt, crashes/
#   fuzz-go      nix run .#fuzz-go -- [outdir]: FUZZ_TIME seconds per target (60)

{ pkgs, lib, versions, goPkgs, src }:

let
  modules = [ "webui" "yangerd" ];

  fuzz-go-src = pkgs.runCommand "infix-fuzz-go-src" { } ''
    mkdir -p "$out"
    ${lib.concatMapStrings (m: ''
      cp -r ${goPkgs.goMods.${m}.vendoredSource}/. "$out/"
      chmod -R +w "$out"
      cp -r ${src}/harness/go/${m}/. "$out/${m}/"
    '') modules}
  '';

  # infix-go-fuzz <srcdir> [outdir]: runs every Fuzz target of the modules in
  # srcdir for FUZZ_TIME seconds each, in a writable copy.
  runner = pkgs.writeShellApplication {
    name = "infix-go-fuzz";
    runtimeInputs = [ versions.go pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gnused ];
    text = ''
      srcdir=$1
      out=''${2:-$(mktemp -d)}
      time=''${FUZZ_TIME:-60}
      mkdir -p "$out/crashes"
      cp -r "$srcdir" "$out/src"
      chmod -R +w "$out/src"
      export HOME=$out GOCACHE=$out/go-cache GOPATH=$out/go
      export GOTOOLCHAIN=local GOPROXY=off CGO_ENABLED=0
      echo "=== Infix Go fuzz targets: $time s each ===" > "$out/summary.txt"
      : > "$out/report.txt"
      failed=0
      for m in ${toString modules}; do
        mode=mod
        if [ -d "$out/src/$m/vendor" ]; then mode=vendor; fi
        while IFS= read -r f; do
          dir=$(dirname "$f")
          pkg=./''${dir#"$out/src/$m/"}
          while IFS= read -r fn; do
            name=''${pkg#./internal/}
            log=$out/$m-''${name//\//_}-$fn.log
            if (cd "$out/src/$m" && GOFLAGS=-mod=$mode \
                go test -run='^$' -fuzz="^$fn\$" -fuzztime="''${time}s" "$pkg") > "$log" 2>&1; then
              status=ok
            else
              status=FAIL
              failed=$((failed + 1))
              mkdir -p "$out/crashes/$m/$fn"
              cp -r "$dir/testdata/fuzz/$fn/." "$out/crashes/$m/$fn/" 2>/dev/null || true
              where=$(grep -m 1 -oE '[A-Za-z0-9_./-]+\.go:[0-9]+' "$log" || echo "fuzz_test.go:0")
              msg=$(grep -m 1 -E 'panic:|fuzz_test.go:[0-9]+: ' "$log" | sed 's/^[[:space:]]*//' || true)
              echo "src/$m/''${pkg#./}/$(basename "''${where%%:*}"):''${where##*:}:0: error: $fn: ''${msg:-failed} [go-fuzz]" \
                >> "$out/report.txt"
            fi
            execs=$(grep -oE 'execs: [0-9]+' "$log" | tail -n 1 || true)
            printf '  %-48s %-5s %s\n' "$m $pkg $fn" "$status" "''${execs:-}" | tee -a "$out/summary.txt"
          done < <(sed -nE 's/^func (Fuzz[A-Za-z0-9_]+).*/\1/p' "$f")
        done < <(find "$out/src/$m" -name fuzz_test.go -not -path '*/vendor/*' | sort)
      done
      chmod -R +w "$out/go" 2>/dev/null || true
      rm -rf "$out/src" "$out/go-cache" "$out/go"
      echo "" >> "$out/summary.txt"
      echo "Failing targets: $failed" | tee -a "$out/summary.txt"
      echo "$failed" > "$out/count.txt"
    '';
  };

  fuzz-go-run = pkgs.runCommand "infix-fuzz-go-run" { } ''
    FUZZ_TIME=10 ${lib.getExe runner} ${fuzz-go-src} "$out"
  '';

  fuzz-go = pkgs.writeShellApplication {
    name = "fuzz-go";
    text = ''exec ${lib.getExe runner} ${fuzz-go-src} "''${1:-fuzz-go-out}"'';
  };
in
{
  packages = { inherit fuzz-go-src fuzz-go-run fuzz-go; };
}
