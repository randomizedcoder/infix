"""Run every compile command in a compile_commands.json again with -fanalyzer.

Usage: gcc-analyzer.py compile_commands.json JOBS
Prints the diagnostics, one "file:line:col: warning: message [-Wanalyzer-...]"
line per finding, sorted.
"""

import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

DIAG = re.compile(r"^[^ :]+:\d+:\d+: warning: .*\[-Wanalyzer-[^\]]+\]$")


def analyzer_args(args):
    """Swap -o <file> for -o /dev/null, drop -Werror*, add -fanalyzer."""
    out, skip = [], False
    for a in args:
        if skip:
            skip = False
            continue
        if a == "-o":
            skip = True
            continue
        if a.startswith("-Werror"):
            continue
        out.append(a)
    return out + ["-fanalyzer", "-fdiagnostics-plain-output", "-o", "/dev/null"]


def run(entry):
    args = entry.get("arguments") or entry["command"].split()
    p = subprocess.run(analyzer_args(args), cwd=entry["directory"],
                       capture_output=True, text=True, check=False)
    return [absolute(line, entry["directory"])
            for line in p.stderr.splitlines() if DIAG.match(line)]


def absolute(line, directory):
    """Make the file name of a diagnostic absolute; libtool builds use relative ones."""
    path, rest = line.split(":", 1)
    return os.path.normpath(os.path.join(directory, path)) + ":" + rest


def main():
    with open(sys.argv[1]) as f:
        entries = json.load(f)
    with ThreadPoolExecutor(max_workers=int(sys.argv[2])) as pool:
        lines = {line for result in pool.map(run, entries) for line in result}
    for line in sorted(lines):
        print(line)


if __name__ == "__main__":
    main()
