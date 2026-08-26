#!/usr/bin/env python3
"""
Generates a maze using randomized recursive backtracker (guarantees a
real maze: exactly one path between any two open cells, with genuine
dead ends), on a "doubled grid" so it maps directly onto our BFS
engine's cell model (where a cell is either fully wall or fully open,
rather than walls existing between cells).

ROOMS_WIDE x ROOMS_TALL "rooms" become a (2*ROOMS_WIDE-1) x
(2*ROOMS_TALL-1) grid, where even (row,col) are always-open room cells
and odd row/col are "connector" cells that are open only if that
passage was carved.
"""
import random

random.seed(42)  # deterministic, reproducible

ROOMS_WIDE = 10
ROOMS_TALL = 8
GRID_WIDTH = 2 * ROOMS_WIDE - 1   # 19
GRID_HEIGHT = 2 * ROOMS_TALL - 1  # 15

# 1 = wall, 0 = open. Start all wall, carve passages.
grid = [[1] * GRID_WIDTH for _ in range(GRID_HEIGHT)]

def room_coord(rr, rc):
    return (2 * rr, 2 * rc)

visited = [[False] * ROOMS_WIDE for _ in range(ROOMS_TALL)]

def carve(rr, rc):
    visited[rr][rc] = True
    r, c = room_coord(rr, rc)
    grid[r][c] = 0
    dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    random.shuffle(dirs)
    for dr, dc in dirs:
        nrr, nrc = rr + dr, rc + dc
        if 0 <= nrr < ROOMS_TALL and 0 <= nrc < ROOMS_WIDE and not visited[nrr][nrc]:
            # open the connector cell between (rr,rc) and (nrr,nrc)
            cr, cc = r + dr, c + dc
            grid[cr][cc] = 0
            carve(nrr, nrc)

carve(0, 0)

start = room_coord(0, 0)
end = room_coord(ROOMS_TALL - 1, ROOMS_WIDE - 1)

# Print ASCII art for a sanity check
for r in range(GRID_HEIGHT):
    row_str = ""
    for c in range(GRID_WIDTH):
        if (r, c) == start:
            row_str += "S"
        elif (r, c) == end:
            row_str += "E"
        else:
            row_str += "#" if grid[r][c] else "."
    print(row_str)

print(f"\nGRID_WIDTH={GRID_WIDTH} GRID_HEIGHT={GRID_HEIGHT}")
print(f"start={start} end={end}")

# Ground-truth BFS in Python
from collections import deque
q = deque([start])
came_from = {start: None}
while q:
    cur = q.popleft()
    if cur == end:
        break
    r, c = cur
    for dr, dc in [(-1,0),(1,0),(0,-1),(0,1)]:
        nr, nc = r+dr, c+dc
        if 0 <= nr < GRID_HEIGHT and 0 <= nc < GRID_WIDTH and grid[nr][nc] == 0 and (nr,nc) not in came_from:
            came_from[(nr,nc)] = cur
            q.append((nr,nc))

path = []
cur = end
while cur is not None:
    path.append(cur)
    cur = came_from.get(cur)
path.reverse()

print(f"\nShortest path length: {len(path)} cells")
print(f"Path: {path}")

# Save wall bits (row-major) for $readmemb
import os
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'rtl', 'bfs', 'maze_data')
os.makedirs(OUT_DIR, exist_ok=True)
with open(os.path.join(OUT_DIR, 'maze1.mem'), 'w') as f:
    for r in range(GRID_HEIGHT):
        for c in range(GRID_WIDTH):
            f.write(f"{grid[r][c]}\n")

# Save ground truth for reference / re-verifying the testbench's expected values
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'maze1_groundtruth.txt'), 'w') as f:
    f.write(f"GRID_WIDTH={GRID_WIDTH}\n")
    f.write(f"GRID_HEIGHT={GRID_HEIGHT}\n")
    f.write(f"start_row={start[0]} start_col={start[1]}\n")
    f.write(f"end_row={end[0]} end_col={end[1]}\n")
    f.write(f"path_length={len(path)}\n")
    ids = [r*GRID_WIDTH+c for (r,c) in path]
    f.write("path_ids=" + ",".join(map(str, ids)) + "\n")
