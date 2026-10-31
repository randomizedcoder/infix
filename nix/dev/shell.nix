# nix/dev/shell.nix
#
# `nix develop`.  inputsFrom pulls in every C component's build inputs, so
# ./configure finds libyang, sysrepo and the rest as in the image.

{ pkgs
, lib
, versions
, cPkgs
, libyang
}:

let
  python = pkgs.python3.withPackages (ps: with ps; [ pytest ]);

  # Each helper in shell-functions/infix.sh as a command, so `nix develop -c
  # infix-host-build` works as well as the interactive shell.
  helpers = map
    (name: pkgs.writeShellApplication {
      inherit name;
      text = ''
        # shellcheck source=/dev/null
        source ${./shell-functions/infix.sh}
        ${name} "$@"
      '';
    })
    [ "infix-help" "infix-host-build" "infix-host-clean" "infix-go-test" "infix-check" "infix-fuzz" "infix-report" ];
in
pkgs.mkShell {
  name = "infix-dev";
  inputsFrom = lib.attrValues cPkgs.byVariant.release;

  packages = (with versions; [
    go
    golangci-lint
    gosec
    govulncheck
    staticcheck
    cppcheck
    flawfinder
    semgrep
    codechecker
    bear
    osv-scanner
    gitleaks
    shellcheck
    ruff
    bandit
    nixpkgs-fmt
    statix
    deadnix
    llvm.clang
    llvm.clang-tools
  ]) ++ helpers ++ [
    python
    pkgs.gopls
    pkgs.mypy
    pkgs.autoconf
    pkgs.automake
    pkgs.libtool
    pkgs.gdb
    pkgs.valgrind
    pkgs.rsync
    libyang # yanglint
  ];

  # As in nix/build/c.nix: _FORTIFY_SOURCE turns unchecked system() results
  # into errors under the components' -Werror.
  NIX_CFLAGS_COMPILE = "-Wno-error=unused-result";

  # statd links journal_retention_stub -static (see nix/build/c.nix).
  INFIX_GLIBC_STATIC = "${pkgs.glibc.static}/lib";

  # Host builds of src/ install here; /output* is in .gitignore.
  shellHook = ''
    export INFIX_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    export INFIX_STAGING=$INFIX_ROOT/output-host/staging
    export PKG_CONFIG_PATH=$INFIX_STAGING/lib/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
    # test-mode includes srx/ headers without asking pkg-config for libsrx.
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -I$INFIX_STAGING/include"
    export NIX_LDFLAGS="$NIX_LDFLAGS -L$INFIX_STAGING/lib"
    export GOTOOLCHAIN=local
    infix-help
  '';
}
