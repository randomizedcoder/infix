"""Table-driven tests for the triage parsers, filters and scoring.

Run: python3 -m unittest discover -s nix/analysis/triage -p 'test_*.py'
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from filters import (
    deduplicate,
    filter_findings,
    is_exempt,
    is_test_code,
    is_third_party,
    load_exemptions,
)
from finding import Finding, normalize_path, normalize_severity
from parsers import parse
from scoring import classify, cross_tool, exposure, score


def F(tool="cppcheck", check="x", sev="warning", file="src/confd/src/a.c", line=1, msg="m"):
    return Finding(tool, check, sev, file, line, msg)


class TestNormalize(unittest.TestCase):
    def test_normalize_path(self):
        cases = [
            {"description": "store prefix stripped",
             "input": "/nix/store/0123456789abcdefghijklmnopqrstuv-source/src/confd/x.c",
             "expected": "src/confd/x.c"},
            {"description": "sandbox work dir stripped", "input": "/build/work/src/statd/y.c",
             "expected": "src/statd/y.c"},
            {"description": "leading ./ stripped", "input": "./board/a.sh", "expected": "board/a.sh"},
            {"description": "double slash collapsed", "input": "src//bin//c.c", "expected": "src/bin/c.c"},
            {"description": "relative path unchanged", "input": "src/webui/main.go",
             "expected": "src/webui/main.go"},
            {"description": "empty stays empty", "input": "", "expected": ""},
            {"description": "short hash is not a store path",
             "input": "/nix/store/abc-x/src/a.c", "expected": "/nix/store/abc-x/src/a.c"},
        ]
        for c in cases:
            with self.subTest(c["description"]):
                self.assertEqual(normalize_path(c["input"]), c["expected"])

    def test_normalize_severity(self):
        cases = [
            {"description": "error", "input": "error", "expected": "error"},
            {"description": "CodeChecker HIGH", "input": "HIGH", "expected": "error"},
            {"description": "CodeChecker CRITICAL", "input": "CRITICAL", "expected": "error"},
            {"description": "cppcheck performance", "input": "performance", "expected": "warning"},
            {"description": "shellcheck note", "input": "note", "expected": "style"},
            {"description": "padded and mixed case", "input": "  Low ", "expected": "style"},
            {"description": "unknown word is a warning", "input": "bogus", "expected": "warning"},
            {"description": "empty is a warning", "input": "", "expected": "warning"},
        ]
        for c in cases:
            with self.subTest(c["description"]):
                self.assertEqual(normalize_severity(c["input"]), c["expected"])


class TestParsers(unittest.TestCase):
    def test_parse(self):
        cases = [
            {"description": "gcc format with check",
             "tool": "clang-tidy",
             "text": "src/confd/src/system.c:555:3: warning: call to system [cert-env33-c]",
             "expected": [("cert-env33-c", "warning", "src/confd/src/system.c", 555)]},
            {"description": "gcc format without check uses severity",
             "tool": "gcc-analyzer", "text": "src/bin/copy.c:10:2: error: oops",
             "expected": [("error", "error", "src/bin/copy.c", 10)]},
            {"description": "gcc format skips source context lines",
             "tool": "cppcheck", "text": "    strcpy(a, b);\n        ^",
             "expected": []},
            {"description": "ruff with fix marker",
             "tool": "ruff", "text": "test/infamy/x.py:3:1: F401 [*] `os` imported but unused",
             "expected": [("F401", "warning", "test/infamy/x.py", 3)]},
            {"description": "ruff syntax error is an error",
             "tool": "ruff", "text": "utils/a.py:1:5: E999 SyntaxError",
             "expected": [("E999", "error", "utils/a.py", 1)]},
            {"description": "flawfinder level 4 is an error",
             "tool": "flawfinder",
             "text": "src/confd/src/x.c:12:3:  [4] (shell) system:This causes a new program to execute",
             "expected": [("shell.system", "error", "src/confd/src/x.c", 12)]},
            {"description": "flawfinder level 2 is a warning",
             "tool": "flawfinder", "text": "src/bin/y.c:7:9:  [2] (buffer) char:Statically-sized arrays",
             "expected": [("buffer.char", "warning", "src/bin/y.c", 7)]},
            {"description": "bandit",
             "tool": "bandit", "text": "utils/z.py:4: HIGH: B602: subprocess call with shell=True",
             "expected": [("B602", "error", "utils/z.py", 4)]},
            {"description": "golangci with linter",
             "tool": "golangci-lint", "text": "src/webui/internal/server/x.go:12:5: G204: Subprocess launched (gosec)",
             "expected": [("G204", "warning", "src/webui/internal/server/x.go", 12)]},
            {"description": "go vet without column or linter",
             "tool": "go-vet", "text": "src/yangerd/a.go:9: unreachable code",
             "expected": [("vet", "warning", "src/yangerd/a.go", 9)]},
            {"description": "gosec from SARIF",
             "tool": "gosec", "text": "src/webui/a.go:40:7: error: G204: Subprocess launched with variable",
             "expected": [("G204", "error", "src/webui/a.go", 40)]},
            {"description": "gosec line without a rule id is skipped",
             "tool": "gosec", "text": "src/webui/a.go:40:7: error: Subprocess launched", "expected": []},
            {"description": "CodeChecker",
             "tool": "codechecker",
             "text": "[HIGH] src/statd/yangerd.c:88:5: Null pointer passed [core.NonNullParamChecker]",
             "expected": [("core.NonNullParamChecker", "error", "src/statd/yangerd.c", 88)]},
            {"description": "libFuzzer crash, check is the harness",
             "tool": "fuzz",
             "text": "src/statd/yangerd.c:120:9: error: heap-buffer-overflow [fuzz_yangerd_frame]",
             "expected": [("fuzz_yangerd_frame", "error", "src/statd/yangerd.c", 120)]},
            {"description": "Go fuzz failure",
             "tool": "go-fuzz",
             "text": "src/yangerd/internal/ipc/ipc.go:41:0: error: FuzzReadFrame: panic: oops [go-fuzz]",
             "expected": [("go-fuzz", "error", "src/yangerd/internal/ipc/ipc.go", 41)]},
            {"description": "fuzz summary lines are not findings",
             "tool": "fuzz", "text": "Total crash inputs: 0   Distinct crashes: 0", "expected": []},
            {"description": "tool without a parser yields nothing",
             "tool": "yanglint", "text": "libyang err : x", "expected": []},
            {"description": "empty report", "tool": "cppcheck", "text": "", "expected": []},
        ]
        for c in cases:
            with self.subTest(c["description"]):
                got = [(f.check_id, f.severity, f.file, f.line) for f in parse(c["tool"], c["text"])]
                self.assertEqual(got, c["expected"])


class TestFilters(unittest.TestCase):
    def test_paths(self):
        cases = [
            {"description": "vendored Go is third party", "fn": is_third_party,
             "input": "src/webui/vendor/x/y.go", "expected": True},
            {"description": "patches are third party", "fn": is_third_party,
             "input": "patches/sysrepo/a.patch", "expected": True},
            {"description": "a file named vendor.go is ours", "fn": is_third_party,
             "input": "src/webui/vendor.go", "expected": False},
            {"description": "confd is ours", "fn": is_third_party,
             "input": "src/confd/src/x.c", "expected": False},
            {"description": "Go test file", "fn": is_test_code, "input": "src/webui/a_test.go", "expected": True},
            {"description": "test framework", "fn": is_test_code, "input": "test/infamy/x.py", "expected": True},
            {"description": "testutil package", "fn": is_test_code,
             "input": "src/yangerd/internal/testutil/x.go", "expected": True},
            {"description": "a name containing test is not test code", "fn": is_test_code,
             "input": "src/test-mode/test-mode.c", "expected": False},
        ]
        for c in cases:
            with self.subTest(c["description"]):
                self.assertEqual(c["fn"](c["input"]), c["expected"])

    def test_filter_findings(self):
        cases = [
            {"description": "ordinary finding kept", "input": F(), "expected": 1},
            {"description": "noise check dropped", "input": F(check="missingIncludeSystem"), "expected": 0},
            {"description": "line 0 dropped", "input": F(line=0), "expected": 0},
            {"description": "no file dropped", "input": F(file=""), "expected": 0},
            {"description": "vendored dropped", "input": F(file="src/yangerd/vendor/a.go"), "expected": 0},
            {"description": "fortify message dropped", "input": F(msg="_FORTIFY_SOURCE requires"), "expected": 0},
        ]
        for c in cases:
            with self.subTest(c["description"]):
                self.assertEqual(len(filter_findings([c["input"]])), c["expected"])

    def test_exemptions(self):
        ex = load_exemptions("# comment\n\nsrc/a.c:10 core.X  # why\nsrc/b.c:5 *  # every check\n")
        cases = [
            {"description": "exact file, line and check", "input": F(file="src/a.c", line=10, check="core.X"),
             "expected": True},
            {"description": "same line, other check", "input": F(file="src/a.c", line=10, check="core.Y"),
             "expected": False},
            {"description": "neighbouring line", "input": F(file="src/a.c", line=11, check="core.X"),
             "expected": False},
            {"description": "wildcard check", "input": F(file="src/b.c", line=5, check="G204"), "expected": True},
            {"description": "wildcard is per line", "input": F(file="src/b.c", line=6, check="G204"),
             "expected": False},
        ]
        for c in cases:
            with self.subTest(c["description"]):
                self.assertEqual(is_exempt(c["input"], ex), c["expected"])

    def test_exemption_needs_reason(self):
        cases = [
            {"description": "no reason", "input": "src/a.c:10 core.X", "expected": ValueError},
            {"description": "empty reason", "input": "src/a.c:10 core.X  #   ", "expected": ValueError},
            {"description": "no line", "input": "src/a.c core.X  # why", "expected": ValueError},
        ]
        for c in cases:
            with self.subTest(c["description"]), self.assertRaises(c["expected"]):
                load_exemptions(c["input"])

    def test_deduplicate(self):
        cases = [
            {"description": "same file, line and check collapse", "input": [F(), F(tool="clang-tidy")],
             "expected": 1},
            {"description": "different line kept", "input": [F(line=1), F(line=2)], "expected": 2},
            {"description": "different check kept", "input": [F(check="a"), F(check="b")], "expected": 2},
            {"description": "empty", "input": [], "expected": 0},
        ]
        for c in cases:
            with self.subTest(c["description"]):
                self.assertEqual(len(deduplicate(c["input"])), c["expected"])


class TestScoring(unittest.TestCase):
    def test_classify(self):
        cases = [
            {"description": "semgrep shell format string is injection",
             "input": F(tool="semgrep", check="infix-shell-format-string"), "expected": "injection"},
            {"description": "gosec G204 is injection", "input": F(tool="gosec", check="G204"),
             "expected": "injection"},
            {"description": "CodeChecker null dereference is memory safety",
             "input": F(tool="codechecker", check="core.NullDereference"), "expected": "memory-safety"},
            {"description": "gcc analyzer leak is a resource issue",
             "input": F(tool="gcc-analyzer", check="-Wanalyzer-malloc-leak"), "expected": "resource"},
            {"description": "gcc analyzer use after free is memory safety",
             "input": F(tool="gcc-analyzer", check="-Wanalyzer-use-after-free"), "expected": "memory-safety"},
            {"description": "secret comparison is auth",
             "input": F(tool="semgrep", check="infix-go-secret-compare"), "expected": "auth-crypto"},
            {"description": "G104 unhandled error is not auth", "input": F(tool="gosec", check="G104"),
             "expected": "resource"},
            {"description": "G101 hardcoded credential is auth", "input": F(tool="gosec", check="G101"),
             "expected": "auth-crypto"},
            {"description": "G304 is path traversal", "input": F(tool="gosec", check="G304"),
             "expected": "path-traversal"},
            {"description": "a 'trace' message is not a race",
             "input": F(tool="clang-format", check="-Wclang-format-violations", msg="trace"),
             "expected": "style"},
            {"description": "a libFuzzer crash is memory safety",
             "input": F(tool="fuzz", check="fuzz_netd_config", msg="SEGV"), "expected": "memory-safety"},
            {"description": "a Go fuzz failure is memory safety",
             "input": F(tool="go-fuzz", check="go-fuzz", msg="panic: index out of range"),
             "expected": "memory-safety"},
            {"description": "a fuzz-named check from another tool is not a crash",
             "input": F(tool="semgrep", check="fuzz-style", msg="x"), "expected": "style"},
            {"description": "clang-format is style",
             "input": F(tool="clang-format", check="-Wclang-format-violations"), "expected": "style"},
        ]
        for c in cases:
            with self.subTest(c["description"]):
                self.assertEqual(classify(c["input"])[0], c["expected"])

    def test_exposure(self):
        cases = [
            {"description": "webui is network facing", "input": "src/webui/internal/a.go", "expected": 3.0},
            {"description": "confd is configuration driven", "input": "src/confd/src/a.c", "expected": 2.0},
            {"description": "other src falls back to src/", "input": "src/factory/factory.c", "expected": 1.0},
            {"description": "test code under webui is capped", "input": "src/webui/a_test.go", "expected": 0.3},
            {"description": "unknown top level", "input": "doc/x.md", "expected": 1.0},
            {"description": "prefix must match from the start", "input": "x/src/webui/a.go", "expected": 1.0},
        ]
        for c in cases:
            with self.subTest(c["description"]):
                self.assertEqual(exposure(c["input"]), c["expected"])

    def test_cross_tool(self):
        cases = [
            {"description": "two tools on one line are one location", "input": [F(tool="a"), F(tool="b")],
             "expected": 1},
            {"description": "two tools within tolerance", "input": [F(tool="a", line=10), F(tool="b", line=13)],
             "expected": 2},
            {"description": "two tools beyond tolerance", "input": [F(tool="a", line=10), F(tool="b", line=14)],
             "expected": 0},
            {"description": "one tool twice is not cross-tool", "input": [F(tool="a"), F(tool="a", line=2)],
             "expected": 0},
            {"description": "different files", "input": [F(tool="a"), F(tool="b", file="src/x.c")],
             "expected": 0},
            {"description": "a formatter does not corroborate",
             "input": [F(tool="flawfinder"), F(tool="clang-format", check="-Wclang-format-violations")],
             "expected": 0},
            {"description": "golangci-lint's gosec is gosec",
             "input": [F(tool="gosec", check="G204"), F(tool="golangci-lint", check="gosec")],
             "expected": 0},
            {"description": "cppcheck and cppcheck-exhaustive are one engine",
             "input": [F(tool="cppcheck"), F(tool="cppcheck-exhaustive")], "expected": 0},
            {"description": "golangci-lint staticcheck and gosec are two engines",
             "input": [F(tool="gosec", check="G204"), F(tool="golangci-lint", check="staticcheck")],
             "expected": 1},
        ]
        for c in cases:
            with self.subTest(c["description"]):
                self.assertEqual(len(cross_tool(c["input"])), c["expected"])

    def test_score(self):
        cases = [
            {"description": "error injection in webui: 3 x 10 x 3",
             "input": [F(tool="gosec", check="G204", sev="error", file="src/webui/a.go")], "expected": 90.0},
            {"description": "style in a test: 1 x 1 x 0.3",
             "input": [F(tool="clang-format", check="-Wclang-format-violations", sev="style",
                         file="test/a.c")], "expected": 0.3},
            {"description": "cross-tool agreement multiplies by 1.5",
             "input": [F(tool="semgrep", check="infix-shell-format-string", file="src/confd/src/a.c"),
                       F(tool="flawfinder", check="shell.system", file="src/confd/src/a.c")],
             "expected": 60.0},
        ]
        for c in cases:
            with self.subTest(c["description"]):
                self.assertEqual(score(c["input"])[0].score, c["expected"])

    def test_order(self):
        ranked = score([F(check="-Wclang-format-violations", tool="clang-format", sev="style"),
                        F(tool="gosec", check="G204", file="src/webui/a.go")])
        self.assertEqual([f.tool for f in ranked], ["gosec", "clang-format"])


if __name__ == "__main__":
    unittest.main()
