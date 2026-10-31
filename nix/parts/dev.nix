# nix/parts/dev.nix
#
# `nix develop`, `nix develop .#buildroot`, `nix run .#buildroot` and `nix fmt`.

{
  perSystem = { infix, pkgs, ... }: {
    devShells = infix.dev.devShells;
    apps.buildroot = {
      type = "app";
      program = "${infix.dev.buildroot}/bin/infix-buildroot";
      meta.description = "Run a command in the Buildroot FHS environment";
    };
    formatter = pkgs.writeShellApplication {
      name = "infix-fmt";
      runtimeInputs = [ pkgs.nixpkgs-fmt ];
      text = ''
        if [ "$#" -eq 0 ]; then
          set -- flake.nix nix
        fi
        exec nixpkgs-fmt "$@"
      '';
    };
  };
}
