"""Compile every runtime script with Lua 5.4 and run the pure-Lua tests.

    python -m pip install lupa
    python tests/run_tests.py
"""
import pathlib
import sys

from lupa import lua54

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "ue4ss" / "TrainingDummy" / "Scripts"
TESTS = ROOT / "tests"


def main() -> int:
    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    check = lua.eval("function(src, name) local f, e = load(src, name); return f ~= nil, e end")
    lua.execute(f'package.path = "{SCRIPTS.as_posix()}/?.lua;" .. package.path')
    failures = 0
    for script in sorted(SCRIPTS.glob("*.lua")):
        compiled, error = check(script.read_text(encoding="utf-8"), "@" + script.name)
        if not compiled:
            print(f"syntax error: {error}")
            failures += 1
    for test in sorted(TESTS.glob("*_test.lua")):
        try:
            lua.execute(test.read_text(encoding="utf-8"))
        except Exception as exc:  # LuaError carries the assertion message
            print(f"{test.name}: FAILED {exc}")
            failures += 1
    print("all passed" if failures == 0 else f"{failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
