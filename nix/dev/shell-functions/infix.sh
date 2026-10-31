# shellcheck shell=bash
# Helper functions for `nix develop` (nix/dev/shell.nix).

infix-help() {
	cat <<-HELP
	Infix dev shell.  Helpers:
	  infix-host-build [component...]  configure + make a copy of src/<component> under
	                                   output-host/build, install into output-host/staging
	                                   (default: libsrx and every C component)
	  infix-host-clean                 remove output-host/ (build copies and staging)
	  infix-go-test [module...]        go test -race in src/<module> (default: all)
	  infix-check [quick|standard|deep] nix build .#analysis-<tier>, print the summary
	  infix-fuzz [seconds]             build the C harnesses and run each one
	  infix-report                     nix build .#analysis-report, print the top findings
	See nix/README.md for every flake target.
	HELP
}

_infix_c_components="libsrx confd statd netd bin klish-plugin-infix gencert rauc-installation-status test-mode factory keyack"
# Read by the helpers that source this file.
# shellcheck disable=SC2034
_infix_go_modules="webui yangerd netbrowse features"

# The feature flags nix/build/c.nix builds with.
_infix_flags() {
	case $1 in
	confd) echo --enable-containers --enable-frr --enable-wifi --enable-gps --enable-console \
		--enable-netbrowse --enable-webui --enable-snmp --enable-netconf-subsystem ;;
	statd) echo --enable-containers --enable-frr ;;
	netd) echo --with-frr-conf ;;
	klish-plugin-infix) echo --enable-containers --enable-snmp --enable-shell ;;
	esac
}

infix-host-build() {
	local c comps=("$@")
	[ ${#comps[@]} -eq 0 ] && read -ra comps <<<"$_infix_c_components"
	local build=$INFIX_ROOT/output-host/build
	mkdir -p "$INFIX_STAGING" "$build"
	for c in "${comps[@]}"; do
		echo "=== $c"
		# A copy, so autoreconf and configure leave src/ untouched.
		rsync -a --exclude vendor "$INFIX_ROOT/src/$c" "$build/" || return 1
		(
			cd "$build/$c" || exit 1
			if [ -f configure.ac ]; then
				[ -x configure ] || autoreconf -fi || exit 1
				[ -f Makefile ] || ./configure --prefix="$INFIX_STAGING" \
					"srpdplugindir=$INFIX_STAGING/lib/sysrepo-plugind/plugins" \
					$(_infix_flags "$c") || exit 1
				if [ "$c" = statd ]; then
					make -j"$(nproc)" "journal_retention_stub_LDFLAGS=-static -L$INFIX_GLIBC_STATIC" && make install
				else
					make -j"$(nproc)" && make install
				fi
			else
				make CFLAGS="-Wall -Wextra -Werror -DRESETME_PATH=/mnt/cfg/infix.reset"
			fi
		) || { echo "infix-host-build: $c failed" >&2; return 1; }
	done
}

infix-host-clean() {
	rm -rf "$INFIX_ROOT/output-host"
}

infix-go-test() {
	local m mods=("$@")
	[ ${#mods[@]} -eq 0 ] && read -ra mods <<<"$_infix_go_modules"
	for m in "${mods[@]}"; do
		echo "=== $m"
		(cd "$INFIX_ROOT/src/$m" && go test -race ./...) || return 1
	done
}

infix-check() {
	local tier=${1:-quick} out
	out=$(nix build "$INFIX_ROOT#analysis-$tier" --no-link --print-out-paths) || return 1
	cat "$out/summary.txt"
	echo "Reports: $out"
}

infix-fuzz() {
	local out
	out=$(nix build "$INFIX_ROOT#fuzz" --no-link --print-out-paths) || return 1
	FUZZ_TIME=${1:-60} "$out/bin/run-fuzzers" "$INFIX_ROOT/output-host/fuzz"
}

infix-report() {
	local out
	out=$(nix build "$INFIX_ROOT#analysis-report" --no-link --print-out-paths) || return 1
	head -60 "$out/triage.md"
	echo "Full report: $out"
}
