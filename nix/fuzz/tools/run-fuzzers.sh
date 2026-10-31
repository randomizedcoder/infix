# infix-fuzz <bindir> <corpus> [outdir]
#
# Runs every fuzz_* harness in bindir, one after another, seeded from corpus/<harness>/
# (or from corpus/ itself when it has no directory for that harness), then reproduces each
# crash it found and keeps one per sanitizer SUMMARY line. Every fuzz target uses this:
# run-fuzzers, fuzz-run and fuzz-deep (nix/fuzz/default.nix).
#
# outdir (default $FUZZ_WORKDIR, else a new temporary directory) gets:
#   <harness>/           the harness's working corpus, and the crash-* inputs it found
#   <harness>.log        libFuzzer's output
#   crashes/<harness>/   crash-<sig> and repro-<sig>.txt for each distinct crash
#   summary.txt          per harness: coverage, crash inputs, distinct crashes
#   count.txt            crash inputs in all; distinct_count.txt: distinct crashes
#   report.txt           per distinct crash, "src/file.c:line:col: error: SUMMARY [fuzz_x]"
#                        at its first stack frame under src/ (what triage reads)
#
# Environment:
#   FUZZ_TIME    seconds per harness (60)
#   FUZZ_FORKS   libFuzzer -fork= jobs, with -ignore_crashes=1 (0: run in-process)
#   FUZZ_MAXLEN  libFuzzer -max_len=
#   FUZZ_MAX_REPRO  crash inputs replayed per harness, smallest first (100); fork mode
#                with -ignore_crashes can write thousands of the same crash
#   FUZZ_DICT    a libFuzzer dictionary for every harness; without it, a harness
#                uses <corpus>/../dict/<harness without fuzz_>.dict when there is one

bindir=$1
corpus=$2
out=${3:-${FUZZ_WORKDIR:-$(mktemp -d)}}
time=${FUZZ_TIME:-60}
forks=${FUZZ_FORKS:-0}
max_repro=${FUZZ_MAX_REPRO:-100}

args=(-max_total_time="$time")
if [ "$forks" -gt 0 ]; then
	args+=(-fork="$forks" -ignore_crashes=1)
fi
if [ -n "${FUZZ_MAXLEN:-}" ]; then
	args+=(-max_len="$FUZZ_MAXLEN")
fi
if [ -n "${FUZZ_DICT:-}" ]; then
	args+=(-dict="$FUZZ_DICT")
fi
export ASAN_OPTIONS=abort_on_error=0:detect_leaks=0:symbolize=1
export UBSAN_OPTIONS=print_stacktrace=1

mkdir -p "$out/crashes"
: >"$out/report.txt"
echo "=== Infix fuzzers: ${time} s per harness, ${forks} fork(s) ===" >"$out/summary.txt"
total=0
distinct=0
for bin in "$bindir"/fuzz_*; do
	name=$(basename "$bin")
	work=$out/$name
	seeds=$corpus/$name
	[ -d "$seeds" ] || seeds=$corpus
	mkdir -p "$work"
	cp -rn "$seeds"/. "$work/" 2>/dev/null || true
	hargs=("${args[@]}")
	dict=$corpus/../dict/${name#fuzz_}.dict
	if [ -z "${FUZZ_DICT:-}" ] && [ -f "$dict" ]; then
		hargs+=(-dict="$dict")
	fi
	"$bin" "${hargs[@]}" -artifact_prefix="$work/" "$work" >"$out/$name.log" 2>&1 || true

	# One crash kept per signature: the SUMMARY line, without addresses.
	declare -A seen=()
	crashes=$(find "$work" -maxdepth 1 -name 'crash-*' | wc -l)
	kept=0
	n=0
	while IFS= read -r crash; do
		n=$((n + 1))
		sig=$("$bin" "$crash" 2>&1 | grep -m 1 -oE 'SUMMARY: .*' | sed 's/0x[0-9a-f]*//g' || true)
		sig=${sig:-unknown-$n}
		hash=$(printf '%s' "$sig" | cksum | cut -d ' ' -f 1)
		if [ -z "${seen[$hash]:-}" ]; then
			seen[$hash]=1
			kept=$((kept + 1))
			mkdir -p "$out/crashes/$name"
			cp "$crash" "$out/crashes/$name/crash-$hash"
			"$bin" "$crash" >"$out/crashes/$name/repro-$hash.txt" 2>&1 || true
			# The first frame in the tree, cut at the first /src/ (the build directory).
			frame=$(grep -m 1 -oE '[^ ]*/src/[^ ]+:[0-9]+:[0-9]+' "$out/crashes/$name/repro-$hash.txt" |
				awk '{ print substr($0, index($0, "/src/") + 1) }' || true)
			echo "${frame:-$name:0:0}: error: ${sig#SUMMARY: } [$name]" >>"$out/report.txt"
		fi
	done < <(find "$work" -maxdepth 1 -name 'crash-*' -printf '%s %p\n' | sort -n | head -n "$max_repro" | cut -d ' ' -f 2-)
	unset seen

	cov=$(grep -oE 'cov: [0-9]+' "$out/$name.log" | tail -n 1 || true)
	printf '  %-20s %-10s %s crash input(s), %s distinct\n' \
		"$name:" "${cov:-cov: ?}" "$crashes" "$kept" | tee -a "$out/summary.txt"
	total=$((total + crashes))
	distinct=$((distinct + kept))
done
{
	echo
	echo "Total crash inputs: $total   Distinct crashes: $distinct   (in $out)"
} | tee -a "$out/summary.txt"
echo "$total" >"$out/count.txt"
echo "$distinct" >"$out/distinct_count.txt"
