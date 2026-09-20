#!/usr/bin/env python3
"""
Runs every CPU test program and checks the results automatically.

Run from the project root: python3 sw/check_runner.py
"""
import subprocess
import re
import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TESTS = [
    ("test1_arith", 20, {
        1: 5, 2: 10, 3: 0xf0, 4: 0x0f,
        5: 15, 6: 0xfffffffb, 7: 0, 8: 0xff,
        9: 1, 10: 8, 11: 20, 12: 1, 13: 3,
    }),
    ("test2_branch", 25, {
        5: 15, 6: 0, 7: 1,
    }),
    ("test3_memory", 15, {
        7: 0x123, 8: 0x2ab,
    }),
    ("test4_jump", 15, {
        1: 4, 2: 42, 3: 0x14, 5: 0x12345000, 6: 7,
        9: 0,
        11: 0,
    }),
    ("test5_edge_cases", 15, {
        0: 0,
        5: 1,
        6: 0,
        7: 0xfffffffc,
        8: 0x7ffffffc,
    }),
]

DEMOS = [
    ("demo_fibonacci", 70, [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]),
    ("demo_bubblesort", 250, [1, 2, 3, 4, 5]),
    ("demo_gameoflife", 30000, [
        0, 5, 6, 2, 0, 0, 0, 0,
        0, 4, 5, 6, 0, 0, 0, 0,
        0, 2, 12, 6, 0, 0, 0, 0,
        0, 4, 8, 14, 0, 0, 0, 0,
    ]),
]

REG_RE = re.compile(r'^x(\d+)\s+=\s+0x([0-9a-fA-F]+)')
CONSOLE_RE = re.compile(r'^CONSOLE:\s+(-?\d+)\s+\(0x([0-9a-fA-F]+)\)')


def assemble_and_simulate(name, cycles):
    asm = os.path.join(ROOT, "sw", f"{name}.asm")
    hexf = os.path.join(ROOT, "sw", f"{name}.hex")

    r = subprocess.run(
        [sys.executable, os.path.join(ROOT, "sw", "assembler.py"), asm, hexf],
        capture_output=True, text=True
    )
    if r.returncode != 0:
        print(f"[{name}] ASSEMBLE FAILED:\n{r.stderr}")
        return None

    r = subprocess.run(
        ["vvp", os.path.join(ROOT, "sim", "tb_cpu.vvp"),
         f"+HEXFILE={os.path.relpath(hexf, ROOT)}", f"+CYCLES={cycles}"],
        capture_output=True, text=True, cwd=ROOT
    )
    if r.returncode != 0:
        print(f"[{name}] SIMULATION FAILED:\n{r.stderr}")
        return None

    return r.stdout


def run_reg_test(name, cycles, expected):
    stdout = assemble_and_simulate(name, cycles)
    if stdout is None:
        return False

    regs = {}
    for line in stdout.splitlines():
        m = REG_RE.match(line.strip())
        if m:
            regs[int(m.group(1))] = int(m.group(2), 16)

    ok = True
    for reg_num, exp_val in expected.items():
        exp_val &= 0xFFFFFFFF
        actual = regs.get(reg_num)
        if actual != exp_val:
            print(f"[{name}] MISMATCH x{reg_num}: "
                  f"expected 0x{exp_val:08x}, got "
                  f"{'0x%08x' % actual if actual is not None else 'MISSING'}")
            ok = False

    print(f"[{name}] {'PASS' if ok else 'FAIL'}")
    return ok


def run_demo(name, cycles, expected_sequence):
    stdout = assemble_and_simulate(name, cycles)
    if stdout is None:
        return False

    printed = []
    for line in stdout.splitlines():
        m = CONSOLE_RE.match(line.strip())
        if m:
            printed.append(int(m.group(1)))

    ok = (printed == expected_sequence)
    if ok:
        print(f"[{name}] PASS  (console output: {printed})")
    else:
        print(f"[{name}] FAIL  expected {expected_sequence}, got {printed}")
    return ok


def main():
    print("---- Directed register-value tests ----")
    reg_results = [run_reg_test(name, cycles, expected) for name, cycles, expected in TESTS]

    print("\n---- Demo programs (checked via console output) ----")
    demo_results = [run_demo(name, cycles, expected) for name, cycles, expected in DEMOS]

    all_names = [t[0] for t in TESTS] + [d[0] for d in DEMOS]
    all_results = reg_results + demo_results

    print("\n==== Summary ====")
    passed = sum(all_results)
    for name, ok in zip(all_names, all_results):
        print(f"  {name}: {'PASS' if ok else 'FAIL'}")
    print(f"{passed}/{len(all_results)} passed")
    sys.exit(0 if passed == len(all_results) else 1)


if __name__ == "__main__":
    main()
