# nix/dev/buildroot-fhs.nix
#
# `nix develop .#buildroot`: Buildroot expects a conventional /usr layout and
# rejects some Nix environment variables, so it runs in an FHS environment with
# the host prerequisites from doc/developers-guide.md (Build, Test).
#
#   nix develop .#buildroot                      an interactive shell inside it
#   make x86_64_defconfig && make
#   nix run .#buildroot -- make x86_64_defconfig  one command inside it
#
# `make test` also needs a working podman or docker on the host: the FHS
# environment sees the host's /run, so a NixOS host's podman wrappers work.

{ pkgs }:

let
  fhs = pkgs.buildFHSEnv {
    name = "infix-buildroot";
    targetPkgs = p: with p; [
      # doc/developers-guide.md, Build
      bc
      binutils
      gcc
      gnumake
      bzip2
      cpio
      diffutils
      file
      findutils
      git
      gzip
      ncurses
      ncurses.dev
      openssl
      openssl.dev
      perl
      patch
      python3
      rsync
      gnused
      gnutar
      unzip
      wget
      gettext # autopoint
      bison
      flex
      autoconf
      automake
      libtool
      mtools
      sbsigntool
      # ... and what Buildroot's dependency check and host packages assume
      which
      util-linux
      pkg-config
      cmake
      zlib
      zlib.dev
      xz
      zstd
      squashfsTools
      e2fsprogs
      dosfstools
      # doc/developers-guide.md, Test
      jq
      graphviz
      qemu
      ethtool
      gdb
      tcpdump
      wireshark-cli
    ];
    # Buildroot refuses to run with these set, or with "." in PATH.
    profile = ''
      unset CC CXX LD AR AS NM RANLIB OBJCOPY OBJDUMP STRIP PKG_CONFIG_PATH LD_LIBRARY_PATH
      export PS1="(infix-buildroot) $PS1"
    '';
    runScript = pkgs.writeShellScript "infix-buildroot-run" ''
      if [ $# -gt 0 ]; then exec "$@"; fi
      exec bash
    '';
  };
in
{
  inherit fhs;
  # Enters the FHS environment only when interactive, so `nix develop -c` still
  # runs its command (in the plain shell, with infix-buildroot on PATH).
  shell = pkgs.mkShell {
    name = "infix-buildroot-shell";
    packages = [ fhs ];
    shellHook = ''
      if [[ $- == *i* ]]; then exec infix-buildroot; fi
    '';
  };
}
