"""Print the preprocessor flags a compile_commands.json gives one source file.

Usage: db-flags.py compile_commands.json src/statd/yangerd.c
Prints -I, -isystem, -include, -D, -U and -std arguments, one per line, with
relative include paths made absolute, so a harness that #includes the file can
be compiled from anywhere with the same view of headers and defines.
"""

import json
import os
import sys

OPTS = ("-isystem", "-include", "-I", "-D", "-U")
PATHS = ("-isystem", "-include", "-I")


def flags(entry):
    args = entry.get("arguments") or entry["command"].split()
    out, it = [], iter(args[1:])
    for a in it:
        if a.startswith("-std="):
            out.append(a)
            continue
        opt = next((o for o in OPTS if a.startswith(o)), None)
        if opt is None:
            continue
        val = a[len(opt):] or next(it, "")
        if opt in PATHS:
            val = os.path.normpath(os.path.join(entry["directory"], val))
        out += [opt, val]
    return out


def main():
    db_path, target = sys.argv[1], os.path.abspath(sys.argv[2])
    with open(db_path) as f:
        db = json.load(f)
    for entry in db:
        if os.path.normpath(os.path.join(entry["directory"], entry["file"])) == target:
            print("\n".join(flags(entry)))
            return
    sys.exit(f"db-flags: {target} is not in {db_path}")


if __name__ == "__main__":
    main()
