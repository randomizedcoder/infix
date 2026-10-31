{
  description = "Infix: Nix flake for host builds, static analysis and fuzzing of src/";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Only for semgrep, whose unstable build fails (patchelf on semgrep-core).
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    # The buildroot submodule's commit; only its package patches are read.
    buildroot = {
      url = "github:kernelkit/buildroot/0cc4437f580a6b21df652c1c220d7d5ab1582e37";
      flake = false;
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      imports = [
        ./nix/parts/scope.nix
        ./nix/parts/deps.nix
        ./nix/parts/build.nix
        ./nix/parts/dev.nix
      ];
    };
}
