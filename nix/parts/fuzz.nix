# nix/parts/fuzz.nix
#
# Fuzzing (../fuzz): the C libFuzzer harnesses and the Go fuzz targets.
# fuzz-selftest is a `nix flake check`.

{
  perSystem = { infix, lib, ... }: {
    inherit (infix.fuzzPkgs) packages checks;
    apps = builtins.mapAttrs (_: drv: { type = "app"; program = lib.getExe drv; }) infix.fuzzPkgs.apps;
  };
}
