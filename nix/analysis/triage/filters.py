"""Which findings to drop, and deduplication."""

import re
from pathlib import Path

# Not Infix's code: patches to other projects, the submodules, build output.
THIRD_PARTY = ("patches/", "buildroot/", "9pm/", "qeneth/", "output/", "output-host/")

# Tool limitations rather than findings about the code.
NOISE_CHECKS = {
    "missingIncludeSystem", "missingInclude", "unmatchedSuppression", "checkersReport",
    "normalCheckLevelMaxBranches", "syntaxError", "preprocessorErrorDirective", "unknownMacro",
    "toomanyconfigs", "clang-diagnostic-error", "-Wcpp",
}

NOISE_MESSAGES = ("_FORTIFY_SOURCE",)

# exemptions.txt: "file:line check  # why", one verified false positive per line;
# check may be * for every check on that line.
_EXEMPTION = re.compile(r"^(\S+):(\d+)\s+(\S+)\s+#\s*\S")


def load_exemptions(text):
    """{(file, line, check)} from exemptions.txt; a line without a reason is an error."""
    out = set()
    for n, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = _EXEMPTION.match(line)
        if not m:
            raise ValueError(f"exemptions.txt:{n}: want 'file:line check  # reason': {line}")
        out.add((m.group(1), int(m.group(2)), m.group(3)))
    return out


EXEMPTIONS = load_exemptions((Path(__file__).parent / "exemptions.txt").read_text())


def is_exempt(f, exemptions=EXEMPTIONS):
    return (f.file, f.line, f.check_id) in exemptions or (f.file, f.line, "*") in exemptions


def is_third_party(path):
    return path.startswith(THIRD_PARTY) or "/vendor/" in "/" + path


def is_test_code(path):
    return (path.startswith("test/") or path.endswith("_test.go")
            or "/testdata/" in path or "/testutil/" in path)


def keep(f):
    return (f.line > 0
            and f.file
            and not is_third_party(f.file)
            and f.check_id not in NOISE_CHECKS
            and not any(m in f.message for m in NOISE_MESSAGES)
            and not is_exempt(f))


def filter_findings(findings):
    return [f for f in findings if keep(f)]


def deduplicate(findings):
    """One finding per (file, line, check); clang tools repeat a header's per TU."""
    seen, out = set(), []
    for f in findings:
        if f.dedup_key() not in seen:
            seen.add(f.dedup_key())
            out.append(f)
    return out
