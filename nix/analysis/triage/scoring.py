"""Score = severity x class weight x exposure, x1.5 when two tools agree.

  severity  error 3, warning 2, style 1
  class     what kind of defect the check finds (CLASSES, first match wins)
  exposure  who can reach the code (EXPOSURE, longest matching path prefix)
"""

import re
from collections import defaultdict

from filters import is_test_code

SEVERITY = {"error": 3, "warning": 2, "style": 1}

# (class, weight, regex over "tool check_id message"), first match wins.
CLASSES = [
    ("injection", 10, (r"infix-shell-format|infix-system-nonliteral|infix-go-request-to-exec"
                      r"|\bG204\b|\bG702\b|CWE-78|CWE-88|\bS60[2-9]\b|\bB60[2-9]\b|shell\.(system|popen)"
                      r"|format-nonliteral|CWE-134|\bS307\b|\bB307\b")),
    ("memory-safety", 9, (r"ArrayBound|NullDereference|null-dereference|use-after-free|double-free"
                         r"|buffer-overflow|out-of-bounds|Wanalyzer-(?!.*leak)(?!fd-)|bufferAccessOutOfBounds"
                         r"|arrayIndexOutOfBounds|nullPointer|uninitvar|core\.|unix\.Malloc|unix\.cstring"
                         r"|infix-unbounded-copy|infix-snprintf-return|buffer\.(strcpy|strcat|sprintf|gets)"
                         r"|security\.insecureAPI|bugprone-not-null-terminated|cert-str|danglingLifetime"
                         r"|invalidFunctionArg|integerOverflow|CWE-787|CWE-120")),
    ("auth-crypto", 7, (r"\bG10[12678]\b|\bG40[1-9]\b|\bG50[1-9]\b|\bG11[24]\b|csrf|secret-compare|CWE-208"
                       r"|CWE-346|forwarded-header|cookie|\bS32[0-9]\b|\bS50[0-9]\b|\bB3[0-2][0-9]\b"
                       r"|\bB50[0-9]\b|password|tls|insecure|\bS105\b|\bS106\b")),
    ("path-traversal", 7, r"\bG30[45]\b|CWE-22|infix-path-format|request-to-path|\bS108\b"),
    ("resource", 4, (r"leak|errcheck|unchecked|\bG104\b|unused-result|resourceLeak|bodyclose"
                    r"|CWE-252|nilerr|deadlock|DATA RACE|concurrency-")),
    ("correctness", 3, (r"bugprone-|cppcheck|clang-analyzer|\bSA\d{4}\b|govet|vet|staticcheck|cert-"
                       r"|\bF8\d\d\b|\bB0\d\d\b|\bE9\d\d\b|misc-|ineffassign|shellcheck SC2(0|1)")),
]
_CLASS_RE = [(n, w, re.compile(rx)) for n, w, rx in CLASSES]

# Who reaches the code: the network (webui, mDNS, the daemons parsing what
# neighbours send), an administrator's configuration (confd), or a local user.
EXPOSURE = {
    "src/webui/": 3.0,
    "src/netbrowse/": 2.5,
    "src/yangerd/": 2.5,
    "src/statd/": 2.0,
    "src/confd/": 2.0,
    "src/libsrx/": 2.0,
    "src/klish-plugin-infix/": 1.5,
    "src/netd/": 1.5,
    "src/bin/": 1.2,
    "board/": 1.0,
    "src/": 1.0,
    "utils/": 0.5,
    "test/": 0.3,
    "nix/": 0.3,
}


def classify(f):
    key = f"{f.tool} {f.check_id} {f.message}"
    for name, weight, rx in _CLASS_RE:
        if rx.search(key):
            return name, weight
    return "style", 1


def exposure(path):
    best = ""
    for prefix in EXPOSURE:
        if path.startswith(prefix) and len(prefix) > len(best):
            best = prefix
    weight = EXPOSURE.get(best, 1.0)
    return min(weight, 0.3) if is_test_code(path) else weight


# Formatters say nothing about a security finding on the same line.
FORMATTERS = {"clang-format", "gofmt", "nix-lint"}


def engine(f):
    """The analyzer behind a finding; one engine run twice is not agreement."""
    if f.tool.startswith("golangci-lint") and (f.check_id == "gosec" or re.match(r"G\d+", f.check_id)):
        return "gosec"
    for prefix in ("golangci-lint", "cppcheck"):
        if f.tool.startswith(prefix):
            return prefix
    return f.tool


def cross_tool(findings, tolerance=3):
    """(file, line) of every finding within `tolerance` lines of one from another engine."""
    by_file = defaultdict(list)
    for f in findings:
        if f.tool not in FORMATTERS:
            by_file[f.file].append(f)
    hits = defaultdict(set)
    for fs in by_file.values():
        fs.sort(key=lambda f: f.line)
        for i, a in enumerate(fs):
            for b in fs[i + 1:]:
                if b.line > a.line + tolerance:
                    break
                if engine(b) != engine(a):
                    hits[(a.file, a.line)].add(b.tool)
                    hits[(b.file, b.line)].add(a.tool)
    return hits


def score(findings):
    """Set category, score and tools on each finding; return them highest first."""
    hits = cross_tool(findings)
    for f in findings:
        f.category, weight = classify(f)
        others = hits.get((f.file, f.line), set())
        f.tools = sorted({f.tool} | others)
        s = SEVERITY.get(f.severity, 1) * weight * exposure(f.file)
        if others and weight > 1:
            s *= 1.5
        f.score = round(s, 1)
    return sorted(findings, key=lambda f: (-f.score, f.file, f.line))
