# nix/dev/default.nix
#
#   default    `nix develop`: the C dependencies, Go, Python and every analysis tool,
#              with the helper functions in shell-functions/
#   buildroot  `nix develop .#buildroot`: an FHS environment for building images
#              with Buildroot (make x86_64_defconfig && make) and running make test

{ callPackage }:

let
  buildroot = callPackage ./buildroot-fhs.nix { };
in
{
  devShells = {
    default = callPackage ./shell.nix { };
    buildroot = buildroot.shell;
  };
  # `nix run .#buildroot -- <command>`
  buildroot = buildroot.fhs;
}
