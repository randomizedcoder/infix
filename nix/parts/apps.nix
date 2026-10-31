# nix/parts/apps.nix
#
# `nix run .#vulncheck`, `.#secrets-scan` and `.#deps-drift` (../apps); deps-drift
# is also a `nix flake check`.

{
  perSystem = { infix, lib, ... }: {
    apps = builtins.mapAttrs (_: drv: { type = "app"; program = lib.getExe drv; }) infix.appPkgs.apps;
    inherit (infix.appPkgs) checks;
  };
}
