#!/usr/bin/env python3
"""Write the pixel Claude animation frames as single-path SVGs."""

from pathlib import Path

COLOR = "#D97757"
HERE = Path(__file__).resolve().parent

BODY = [
    "..................",
    "...############...",
    "...##.######.##...",
    ".################.",
    "...############...",
    "....#.#....#.#....",
]


def frame(**rows: str) -> list[str]:
    grid = list(BODY)
    for key, row in rows.items():
        grid[int(key[1:])] = row
    return grid


FRAMES = {
    "clawd": BODY,
    "clawd-blink": frame(r2="...############..."),
    "clawd-walk-a": BODY,
    "clawd-walk-b": frame(r5="...#.#......#.#..."),
    "clawd-wave-mid": frame(
        r2="...##.######.####.",
        r3=".##############...",
    ),
    "clawd-wave-up": frame(
        r0="................#.",
        r1="...############.#.",
        r2="...##.######.###..",
        r3=".##############...",
    ),
    "clawd-cheer": frame(
        r0=".#..............#.",
        r1=".#.############.#.",
        r2="..###.######.###..",
        r3="...############...",
    ),
    "clawd-type-a": frame(
        r3="...##############.",
        r4=".##############...",
    ),
    "clawd-type-b": frame(
        r3=".##############...",
        r4="...##############.",
    ),
    "clawd-look-l": frame(r2="...#.######.###..."),
    "clawd-look-r": frame(r2="...###.######.#..."),
}


def svg(grid: list[str]) -> str:
    runs = []
    for y, row in enumerate(grid):
        x = 0
        while x < len(row):
            if row[x] == "#":
                start = x
                while x < len(row) and row[x] == "#":
                    x += 1
                width = x - start
                runs.append(f"M{start} {y * 2}h{width}v2h-{width}z")
            else:
                x += 1
    width = len(grid[0])
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {len(grid) * 2}">'
        f'<path fill="{COLOR}" d="{"".join(runs)}"/></svg>\n'
    )


def main() -> None:
    for name, grid in FRAMES.items():
        assert all(len(row) == len(grid[0]) for row in grid), name
        (HERE / f"{name}.svg").write_text(svg(grid))


if __name__ == "__main__":
    main()
