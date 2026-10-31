# nix/build/go.nix
#
# The Go modules under src/: webui, yangerd, netbrowse, features.
#
#   <module>          the binaries, built as Buildroot does (CGO_ENABLED=0)
#   go-test           `go test -race ./...` in every module
#   go-test-<module>  one module
#
# goMods.<module> carries what the analysis and fuzzing reuse (the xtcp2
# nix/lib/goModules.nix pattern):
#   vendoredSource  src/<module> (and src/features) with vendor/ filled in, so every Go
#                   check runs offline in the sandbox with GOFLAGS=-mod=vendor
#   goModules       that vendor/ tree on its own
#
# A vendorHash goes stale when a go.sum changes; the build then prints the new
# one ("got: sha256-..."), which goes into vendorHashes below.

{ pkgs, lib, infixLib, versions }:

let
  # null: the module has no dependencies, so nothing to vendor.
  vendorHashes = {
    webui = "sha256-vZ6tGuO8sFvCK7RB6pvme/6xwDWSygYY8IV2+hVjPYo=";
    yangerd = "sha256-ws3uBoOAJoUIevW2az33Hz0Y1AsEaX682yxWobwd/P8=";
    netbrowse = null;
    features = null;
  };

  mkModule = name:
    let
      src = infixLib.srcFor name;
      vendorHash = vendorHashes.${name};
      pkg = versions.buildGoModule {
        pname = name;
        inherit (infixLib) version;
        inherit src vendorHash;
        modRoot = "src/${name}";
        env.CGO_ENABLED = "0";
        env.GOTOOLCHAIN = "local";
        ldflags = [ "-s" "-w" ];
        doCheck = false;
        meta = infixLib.meta // { mainProgram = name; };
      };
    in
    {
      inherit pkg src;
      goModules = pkg.goModules or null;
      vendoredSource = pkgs.runCommand "infix-${name}-vendored-source" { } ''
        cp -r ${src}/src $out
        chmod -R +w $out
        ${lib.optionalString (vendorHash != null) "cp -r ${pkg.goModules} $out/${name}/vendor"}
      '';
    };

  goMods = lib.genAttrs infixLib.goModules mkModule;

  # goCheck name script: runs script in a writable copy of a module's vendored
  # source with the pinned Go, offline; the script writes $out.
  goCheck = { name, module, tools ? [ ], script, cgo ? false }:
    pkgs.runCommandCC "infix-${name}-${module}"
      { nativeBuildInputs = [ versions.go ] ++ tools; } ''
      cp -r ${goMods.${module}.vendoredSource} src && chmod -R +w src && cd src/${module}
      export HOME=$TMPDIR GOCACHE=$TMPDIR/go-cache GOPATH=$TMPDIR/go
      export GOTOOLCHAIN=local GOFLAGS=-mod=${if vendorHashes.${module} != null then "vendor" else "mod"} GOPROXY=off
      export CGO_ENABLED=${if cgo then "1" else "0"}
      ${script}
    '';

  goTest = module: goCheck {
    name = "go-test";
    inherit module;
    cgo = true;
    script = ''
      mkdir -p $out
      go test -race -count=1 ./... 2>&1 | tee $out/report.txt
      test "''${PIPESTATUS[0]}" -eq 0
    '';
  };
  tests = lib.genAttrs infixLib.goModules goTest;
in
{
  inherit goMods goCheck;

  packages = lib.mapAttrs (_: m: m.pkg) goMods
    // lib.mapAttrs' (n: v: lib.nameValuePair "go-test-${n}" v) tests
    // {
    go-test = pkgs.linkFarm "infix-go-test" (lib.mapAttrsToList (n: v: { name = n; path = v; }) tests);
  };
  checks = { inherit (tests) webui yangerd netbrowse features; };
}
