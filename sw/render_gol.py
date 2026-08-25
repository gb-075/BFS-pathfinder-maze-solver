#!/usr/bin/env python3
"""
Renders the Game of Life demo's console output as ASCII art.

The core prints one packed byte per row (bit c = cell (r,c) alive/dead).
This script runs the simulation, captures those values, and renders each
generation as an 8x8 grid using '#' for alive and '.' for dead - purely a
host-side visualization step. All the actual computation (neighbor
counting, the Life rule, grid state) happens on the simulated CPU; this
script just decodes the printed bit patterns into something readable.

Usage: python3 sw/render_gol.py
"""
import subprocess
import re
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRID_SIZE = 8
GENERATIONS = 4

CONSOLE_RE = re.compile(r'^CONSOLE:\s+(-?\d+)')


def main():
    hexf = os.path.join(ROOT, "sw", "demo_gameoflife.hex")
    asm = os.path.join(ROOT, "sw", "demo_gameoflife.asm")

    subprocess.run(["python3", os.path.join(ROOT, "sw", "assembler.py"), asm, hexf], check=True)

    r = subprocess.run(
        ["vvp", os.path.join(ROOT, "sim", "tb_cpu.vvp"),
         f"+HEXFILE={os.path.relpath(hexf, ROOT)}", "+CYCLES=30000"],
        capture_output=True, text=True, cwd=ROOT
    )

    rows = []
    for line in r.stdout.splitlines():
        m = CONSOLE_RE.match(line.strip())
        if m:
            rows.append(int(m.group(1)) & 0xFF)

    expected = GRID_SIZE * GENERATIONS
    if len(rows) != expected:
        print(f"WARNING: expected {expected} printed rows, got {len(rows)}")

    for gen in range(GENERATIONS):
        print(f"-- Generation {gen} --")
        chunk = rows[gen * GRID_SIZE:(gen + 1) * GRID_SIZE]
        for row_val in chunk:
            line = ''.join('#' if (row_val >> c) & 1 else '.' for c in range(GRID_SIZE))
            print(line)
        print()


if __name__ == "__main__":
    main()
