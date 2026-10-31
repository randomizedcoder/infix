"""triage <tier-dir> [--output-dir DIR] [--top N]

Reads every <tool>/report.txt under a tier result (nix build .#analysis-deep),
drops third-party code and tool noise, deduplicates, scores and ranks.
Without --output-dir it prints the top findings.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from filters import deduplicate, filter_findings
from parsers import load
from reports import write_all
from scoring import score


def main():
    ap = argparse.ArgumentParser(prog="triage")
    ap.add_argument("result_dir")
    ap.add_argument("--output-dir")
    ap.add_argument("--top", type=int, default=60)
    args = ap.parse_args()

    raw = load(args.result_dir)
    findings = score(deduplicate(filter_findings(raw)))
    print(f"{len(raw)} raw -> {len(findings)} after filtering and deduplication", file=sys.stderr)
    if args.output_dir:
        write_all(findings, args.output_dir, args.top)
    else:
        for f in findings[:args.top]:
            print(f"{f.score:6.1f}  {f.category:<14} {f.file}:{f.line}  {f.check_id}  {f.message}")


if __name__ == "__main__":
    main()
