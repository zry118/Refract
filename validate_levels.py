#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""关卡设计与校验。

用坐标描述关卡，避免手写字符网格时数错位置。
校验器会暴力枚举所有镜面朝向，确认：可解、初始不是已解、给出最少步数。
全部通过后输出可直接粘进 Swift 的字符网格。
"""

from itertools import product

DIRS = {'>': (1, 0), '<': (-1, 0), '^': (0, -1), 'v': (0, 1)}


def build(width, height, sources, mirrors, targets, walls=(), fixed=()):
    """生成字符网格。mirrors/fixed 都是 [(x, y, char)]"""
    g = [['.'] * width for _ in range(height)]
    for (x, y) in walls:
        g[y][x] = '#'
    for (x, y, c) in fixed:
        g[y][x] = c          # 'o' = 固定 '/'，'p' = 固定 '\'
    for (x, y, c) in mirrors:
        g[y][x] = c
    for (x, y) in targets:
        g[y][x] = 'T'
    for (x, y, d) in sources:
        g[y][x] = d
    return [''.join(row) for row in g]


def trace(grid, mirrors):
    h, w = len(grid), len(grid[0])
    lit, path = set(), []
    for y in range(h):
        for x in range(w):
            c = grid[y][x]
            if c not in DIRS:
                continue
            dx, dy = DIRS[c]
            cx, cy = x, y
            for _ in range(w * h * 4):
                nx, ny = cx + dx, cy + dy
                if not (0 <= nx < w and 0 <= ny < h):
                    break
                cx, cy = nx, ny
                path.append((cx, cy))
                cell = grid[cy][cx]
                if cell == '#':
                    break
                if cell == 'T':
                    lit.add((cx, cy))
                m = mirrors.get((cx, cy))
                if m == '/':
                    dx, dy = -dy, -dx
                elif m == '\\':
                    dx, dy = dy, dx
    return lit, path


def targets_of(grid):
    return {(x, y) for y in range(len(grid)) for x in range(len(grid[0])) if grid[y][x] == 'T'}


def analyze(name, grid):
    tgt = targets_of(grid)
    rots = [(x, y) for y in range(len(grid)) for x in range(len(grid[0]))
            if grid[y][x] in '/\\']
    fixed = {}
    for y in range(len(grid)):
        for x in range(len(grid[0])):
            if grid[y][x] == 'o':
                fixed[(x, y)] = '/'
            elif grid[y][x] == 'p':
                fixed[(x, y)] = '\\'

    if not tgt:
        return f"{name}: 没有目标", False
    if len(rots) > 12:
        return f"{name}: 镜子太多（{len(rots)}）", False

    initial = {(x, y): grid[y][x] for (x, y) in rots}
    lit0, _ = trace(grid, {**fixed, **initial})
    if tgt <= lit0:
        return f"{name}: 初始已解", False

    sols = []
    for combo in product('/\\', repeat=len(rots)):
        m = dict(fixed)
        for pos, v in zip(rots, combo):
            m[pos] = v
        lit, _ = trace(grid, m)
        if tgt <= lit:
            sols.append(combo)

    if not sols:
        return f"{name}: 无解", False

    dist = lambda c: sum(1 for pos, v in zip(rots, c) if initial[pos] != v)
    best = min(sols, key=dist)
    tag = "唯一解" if len(sols) == 1 else f"{len(sols)} 解"
    return (f"{name}: OK  最少 {dist(best)} 步，{tag}，"
            f"镜子 {len(rots)}，目标 {len(tgt)}"), True


# ============ 关卡定义 ============

LEVELS = []

LEVELS.append(("01 折下来", build(
    8, 5,
    sources=[(1, 1, '>')],
    mirrors=[(5, 1, '/')],
    targets=[(5, 4)],
)))

LEVELS.append(("02 接力", build(
    8, 5,
    sources=[(1, 1, '>')],
    mirrors=[(5, 1, '/'), (5, 3, '\\')],
    targets=[(2, 3)],
)))

LEVELS.append(("03 串起来", build(
    8, 5,
    sources=[(1, 1, '>')],
    mirrors=[(5, 1, '/'), (5, 3, '\\')],
    targets=[(4, 3), (2, 3)],
)))

LEVELS.append(("04 三个弯", build(
    9, 7,
    sources=[(1, 1, '>')],
    mirrors=[(6, 1, '/'), (6, 4, '\\'), (2, 4, '/')],
    targets=[(2, 6)],
)))

LEVELS.append(("05 两路夹击", build(
    9, 7,
    sources=[(1, 1, '>'), (1, 5, '>')],
    mirrors=[(5, 1, '/'), (5, 5, '\\')],
    targets=[(5, 3)],
)))

LEVELS.append(("06 固定镜", build(
    9, 5,
    sources=[(1, 1, '>')],
    mirrors=[(6, 3, '/')],
    fixed=[(6, 1, 'p')],
    targets=[(7, 3)],
)))

LEVELS.append(("07 长链", build(
    9, 7,
    sources=[(1, 1, '>')],
    mirrors=[(8, 1, '/'), (8, 5, '\\'), (2, 5, '\\')],
    targets=[(2, 6)],
)))

LEVELS.append(("08 各行其道", build(
    9, 7,
    sources=[(1, 1, '>'), (1, 6, '>')],
    mirrors=[(7, 1, '/'), (4, 6, '\\')],
    targets=[(7, 4), (4, 4)],
)))

if __name__ == "__main__":
    ok = 0
    good = []
    for name, grid in LEVELS:
        line, passed = analyze(name, grid)
        print(line)
        if passed:
            ok += 1
            good.append((name, grid))
    print(f"\n可解关卡 {ok}/{len(LEVELS)}")

    if ok == len(LEVELS):
        print("\n===== 可直接粘贴到 Swift 的关卡数据 =====")
        for name, grid in good:
            rows = ",\n".join(f'            "{r}"' for r in grid)
            print(f'        Level(name: "{name}", rows: [\n{rows}\n        ]),')
