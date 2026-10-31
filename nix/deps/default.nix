# nix/deps/default.nix
#
# The libraries Infix builds against that nixpkgs lacks or has at another version.
# The pins match the Buildroot that the buildroot submodule points at, and the
# `deps-drift` check fails when they no longer do:
#
#   libyang  buildroot/package/libyang/libyang.mk   (nixpkgs has 3.13)
#   sysrepo  buildroot/package/sysrepo/sysrepo.mk   + its patches + patches/sysrepo/<ver>/
#   faux     package/faux/faux.mk
#   klish    package/klish/klish.mk
#
# libite, sysklogd, watchdogd, libconfuse, jansson and the rest come from nixpkgs.

{ pkgs, lib, buildroot }:

let
  pins = import ./pins.nix;

  libyang = pkgs.libyang.overrideAttrs (old: {
    version = pins.libyang.version;
    src = pkgs.fetchFromGitHub {
      owner = "CESNET";
      repo = "libyang";
      rev = "v${pins.libyang.version}";
      inherit (pins.libyang) hash;
    };
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DENABLE_TESTS=OFF" "-DENABLE_VALGRIND_TESTS=OFF" ];
    doCheck = false;
  });

  patchesIn = dir: map (f: dir + "/${f}")
    (lib.sort lib.lessThan (lib.filter (lib.hasSuffix ".patch") (lib.attrNames (builtins.readDir dir))));

  sysrepo = pkgs.stdenv.mkDerivation {
    pname = "sysrepo";
    inherit (pins.sysrepo) version;
    src = pkgs.fetchFromGitHub {
      owner = "sysrepo";
      repo = "sysrepo";
      rev = "v${pins.sysrepo.version}";
      inherit (pins.sysrepo) hash;
    };
    # Buildroot's own patches first, then Infix's, as Buildroot applies them.
    patches = patchesIn "${buildroot}/package/sysrepo"
      ++ patchesIn (../../patches/sysrepo + "/${pins.sysrepo.version}");
    nativeBuildInputs = [ pkgs.cmake pkgs.pkg-config ];
    buildInputs = [ libyang pkgs.pcre2 ];
    cmakeFlags = [
      "-DCMAKE_INSTALL_LIBDIR=lib"
      "-DCMAKE_INSTALL_INCLUDEDIR=include"
      "-DENABLE_EXAMPLES=OFF"
      "-DENABLE_TESTS=OFF"
      "-DENABLE_VALGRIND_TESTS=OFF"
      "-DREPO_SHM_SETUP=OFF"
      "-DNOTIFD_SETUP=OFF"
      "-DINSTALL_SYSREPO_MODULES=OFF"
      # Host builds only link against sysrepo; keep its repository out of /etc.
      "-DREPO_PATH=${placeholder "out"}/etc/sysrepo"
    ];
    meta.license = lib.licenses.bsd3;
  };

  faux = pkgs.stdenv.mkDerivation {
    pname = "faux";
    version = "0-unstable-${lib.substring 0 8 pins.faux.rev}";
    src = pkgs.fetchFromGitHub {
      owner = "kernelkit";
      repo = "faux";
      inherit (pins.faux) rev hash;
    };
    nativeBuildInputs = [ pkgs.autoreconfHook ];
    meta.license = lib.licenses.bsd3;
  };

  klish = pkgs.stdenv.mkDerivation {
    pname = "klish";
    version = "0-unstable-${lib.substring 0 8 pins.klish.rev}";
    src = pkgs.fetchFromGitHub {
      owner = "kernelkit";
      repo = "klish";
      inherit (pins.klish) rev hash;
    };
    nativeBuildInputs = [ pkgs.autoreconfHook pkgs.pkg-config ];
    buildInputs = [ faux pkgs.libxml2 ];
    configureFlags = [ "--with-libxml2" ];
    meta.license = lib.licenses.bsd3;
  };
in
{
  inherit pins libyang sysrepo faux klish;
}
