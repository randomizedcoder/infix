# nix/parts/scope.nix
#
# Builds the package scope (../scope.nix) once per system and hands it to every
# other part as the perSystem argument `infix`.

{ inputs, ... }:

{
  perSystem = { pkgs, ... }: {
    _module.args.infix = import ../scope.nix { inherit pkgs inputs; };
  };
}
