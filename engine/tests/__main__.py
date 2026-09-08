"""Run the whole engine test suite:

    python3 -m engine.tests

Discovers every engine/tests/test_*.py module and calls its run() -> int (0 = pass).
Exits non-zero if any module fails. This is what CI runs (see .github/workflows/deploy.yml).
"""
from __future__ import annotations

import importlib
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def main() -> int:
    modules = sorted(p.stem for p in HERE.glob("test_*.py"))
    if not modules:
        print("no test_*.py modules found")
        return 1
    failed = []
    for name in modules:
        mod = importlib.import_module("engine.tests.{}".format(name))
        run = getattr(mod, "run", None)
        if run is None:
            print("  SKIP {} (no run())".format(name))
            continue
        print("=== {} ===".format(name))
        rc = run()
        if rc:
            failed.append(name)
    print("\n" + "-" * 52)
    if failed:
        print("FAIL: {}".format(", ".join(failed)))
        return 1
    print("all {} engine test modules pass".format(len(modules)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
