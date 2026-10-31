# nix/parts/build.nix
#
# Host builds of src/ (../build): the C components and the Go modules.

{
  perSystem = { infix, lib, ... }: {
    packages = infix.cPkgs.packages // infix.goPkgs.packages // { compile-db = infix.compileDb; };
    checks = lib.mapAttrs' (n: v: lib.nameValuePair "build-${n}" v) infix.cPkgs.checks
      // lib.mapAttrs' (n: v: lib.nameValuePair "go-test-${n}" v) infix.goPkgs.checks;
  };
}
