#!/usr/bin/env python3
"""Write the pixel Claude animation frames and outfit overlays as SVGs."""

from pathlib import Path

COLOR = "#D97757"
DROP = "#7FBBB3"
HERE = Path(__file__).resolve().parent
HAT_ROWS = 4
PALETTE = {
    "o": COLOR,
    "k": "#1E2326",
    "y": "#DBBC7F",
    "g": "#A7C080",
    "t": "#83C092",
    "r": "#E67E80",
    "w": "#E9E2D0",
    "p": "#9B7FC4",
    "b": "#7FBBB3",
    "d": "#5C6A72",
    "s": "#C9A96B",
    "n": "#3A5A8C",
    "pk": "#F0A8C8",
    "e": "#8F4A30",
    "x": "#B5AE98",
    "h": "#8B6B4A",
    "m": "#5E9A92",
}

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
    "clawd-sweat-a": frame(
        r0="................~.",
        r1="...############.~~",
    ),
    "clawd-sweat-b": frame(
        r1="...############.~.",
        r2="...##.######.##.~~",
    ),
}


def runs(grid: list[str], mark: str, tall: int = 2) -> str:
    out = []
    for y, row in enumerate(grid):
        x = 0
        while x < len(row):
            if row[x] == mark:
                start = x
                while x < len(row) and row[x] == mark:
                    x += 1
                width = x - start
                out.append(f"M{start} {y * tall}h{width}v{tall}h-{width}z")
            else:
                x += 1
    return "".join(out)


def svg(grid: list[str]) -> str:
    drop = runs(grid, "~")
    extra = f'<path fill="{DROP}" d="{drop}"/>' if drop else ""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {len(grid[0])} {len(grid) * 2}">'
        f'<path fill="{COLOR}" d="{runs(grid, "#")}"/>{extra}</svg>\n'
    )


FULL = {
    "clawd-squish": [
        "..................",
        "..................",
        "..................",
        "...############...",
        "...############...",
        "...##.######.##...",
        ".################.",
        ".################.",
        "..##############..",
        "..##############..",
        "....#.#....#.#....",
        "....#.#....#.#....",
    ],
    "clawd-happy": [
        "..................",
        "..................",
        "...############...",
        "...############...",
        "...##.######.##...",
        "...#.#.####.#.#...",
        ".################.",
        ".################.",
        "...############...",
        "...############...",
        "....#.#....#.#....",
        "....#.#....#.#....",
    ],
}


def svg_grid(grid: list[str]) -> str:
    marks = dict.fromkeys(c for row in grid for c in row if c != ".")
    paths = "".join(
        f'<path fill="{COLOR if m == "#" else PALETTE[m]}" d="{runs(grid, m, 1)}"/>'
        for m in marks
    )
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {len(grid[0])} {len(grid)}">{paths}</svg>\n'


def paint(grid: list[str], cells: list[tuple[int, int]], mark: str) -> list[str]:
    rows = [list(row) for row in grid]
    for x, y in cells:
        rows[y][x] = mark
    return ["".join(row) for row in rows]


def shut(grid: list[str], row: int) -> list[str]:
    return paint(
        paint(grid, [(5, row - 1), (12, row - 1)], "#"), [(5, row), (12, row)], "e"
    )


def tall(grid: list[str]) -> list[str]:
    return [row for row in grid for _ in (0, 1)]


def floor(grid: list[str]) -> list[str]:
    return ["." * 18] * (12 - len(grid)) + grid


def yawn(big: bool) -> list[str]:
    mouth = [(x, y) for x in range(7, 11) for y in (8, 9)] if big else [(8, 8), (9, 8)]
    return paint(shut(tall(FRAMES["clawd-cheer"]), 5), mouth, "k")


def nod(drop: int) -> list[str]:
    squish = FULL["clawd-squish"]
    head = squish if drop < 0 else shut(squish, 5)
    shift = 1 if drop > 1 else 0
    rows = [list(row) if y > 9 else ["."] * 18 for y, row in enumerate(squish)]
    for y in range(10):
        for x, c in enumerate(head[y]):
            if c != "." and 0 <= y + drop < 12 and x + shift < 18:
                rows[y + drop][x + shift] = c
    return ["".join(row) for row in rows]


def box(
    width: int, height: int, rects: list[tuple[int, int, int, int, str]]
) -> list[str]:
    rows = [["."] * width for _ in range(height)]
    for x0, y0, w, h, mark in rects:
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                rows[y][x] = mark
    return ["".join(row) for row in rows]


def blanket(top: int) -> list[str]:
    stripes = [(x, top + 2, 3, 1, "m") for x in range(3, 23, 6)]
    return box(
        24,
        7,
        [
            (0, top, 24, 7 - top, "b"),
            (0, top, 24, 1, "m"),
            (0, 6, 24, 1, "m"),
            *stripes,
        ],
    )


LIE = [
    "...############...",
    "...##.######.##...",
    ".################.",
    ".################.",
    "..##############..",
]

FULL |= {
    "clawd-sleepy": shut(tall(BODY), 5),
    "clawd-yawn-a": yawn(False),
    "clawd-yawn-b": yawn(True),
    "clawd-doze": shut(FULL["clawd-squish"], 5),
    "clawd-nod-up": nod(-1),
    "clawd-nod-1": nod(1),
    "clawd-nod-2": nod(2),
    "clawd-nod-3": nod(3),
    "clawd-lie": floor(LIE),
    "clawd-lie-blink": floor(paint(LIE, [(5, 1), (12, 1)], "#")),
    "clawd-lie-sl": floor(shut(LIE, 1)),
    "clawd-lie-in": floor(shut([LIE[0], *LIE], 2)),
}

PROPS = {
    "clawd-book-a": [
        "ggggggggggg",
        "gwwwwdwwwwg",
        "gwxxwdwxxwg",
        "gwwwwdwwwwg",
        "gwxxwdwxxwg",
        "ggggggggggg",
    ],
    "clawd-book-b": [
        "ggggggggggg",
        "gwxxwdwxxwg",
        "gwwwwdwwwwg",
        "gwxxwdwxxwg",
        "gwwwwdwwwwg",
        "ggggggggggg",
    ],
    "clawd-book-f": [
        "ggggggggggg",
        "gwwwwdwwwwg",
        "gwwwwdwwwwg",
        "gwwwwdwwwwg",
        "gwwwwdwwwwg",
        "ggggggggggg",
    ],
    "clawd-mug": ["xxxx.", "wwwww", "wwwww", "wwww."],
    "clawd-z-s": ["bbbb", "..b.", ".b..", "bbbb"],
    "clawd-z-l": ["bbbbb", "...b.", "..b..", ".b...", "bbbbb"],
    "clawd-bang": ["r", "r", "r", ".", "r"],
    "clawd-bed": box(
        36,
        10,
        [
            (3, 4, 8, 2, "w"),
            (0, 0, 3, 10, "h"),
            (33, 4, 3, 6, "h"),
            (0, 8, 36, 2, "h"),
            (3, 6, 30, 2, "w"),
        ],
    ),
    "clawd-blanket-a": blanket(1),
    "clawd-blanket-b": blanket(0),
}


Span = tuple[int, int, int, str] | tuple[int, int, int, str, int]

OUTFITS: dict[str, list[Span]] = {
    "party": [
        (-3, 8, 9, "y"),
        (-2, 8, 9, "t"),
        (-1, 7, 10, "r"),
        (0, 7, 10, "t"),
        (1, 6, 11, "r"),
    ],
    "hard": [(-1, 6, 11, "y"), (0, 4, 13, "y"), (1, 2, 15, "s")],
    "phones": [
        (0, 5, 12, "d"),
        (1, 4, 4, "d"),
        (1, 13, 13, "d"),
        (2, 2, 3, "k"),
        (3, 2, 3, "k"),
        (4, 2, 3, "k"),
        (2, 14, 15, "k"),
        (3, 14, 15, "k"),
        (4, 14, 15, "k"),
    ],
    "crown": [
        (-1, 5, 5, "y"),
        (-1, 8, 9, "y"),
        (-1, 12, 12, "y"),
        (0, 5, 12, "y"),
        (1, 5, 12, "y"),
        (1, 8, 9, "r"),
    ],
    "witch": [
        (-3, 9, 10, "p"),
        (-2, 8, 10, "p"),
        (-1, 7, 10, "p"),
        (0, 6, 11, "p"),
        (1, 2, 15, "p"),
        (0, 6, 11, "y", 2),
    ],
    "santa": [
        (-3, 13, 14, "w"),
        (-2, 11, 13, "r"),
        (-1, 7, 12, "r"),
        (0, 5, 12, "r"),
        (1, 3, 14, "w"),
    ],
    "night": [(-2, 14, 15, "y"), (-1, 11, 14, "n"), (0, 5, 12, "n"), (1, 3, 14, "n")],
    "bow": [
        (-2, 10, 11, "pk"),
        (-2, 14, 15, "pk"),
        (-1, 10, 15, "pk"),
        (-1, 12, 13, "r"),
        (0, 10, 11, "pk"),
        (0, 14, 15, "pk"),
        (6, 4, 4, "pk"),
        (6, 13, 13, "pk"),
    ],
    "cat": [
        (-1, 3, 3, "o"),
        (-1, 14, 14, "o"),
        (0, 3, 4, "o"),
        (0, 13, 14, "o"),
        (1, 3, 5, "o"),
        (1, 12, 14, "o"),
        (1, 4, 4, "pk"),
        (1, 13, 13, "pk"),
        (6, 4, 4, "pk"),
        (6, 13, 13, "pk"),
    ],
    "magical": [
        (0, 8, 9, "pk"),
        (-1, 8, 9, "w"),
        (1, 5, 12, "y"),
        (0, 6, 6, "y"),
        (0, 11, 11, "y"),
        (6, 4, 4, "pk"),
        (6, 13, 13, "pk"),
    ],
    "astro": [
        (-3, 6, 11, "b"),
        (-2, 4, 5, "b"),
        (-2, 12, 13, "b"),
        (-1, 3, 3, "b"),
        (-1, 14, 14, "b"),
        *[(y, x, x, "b") for y in range(6) for x in (2, 15)],
        (-2, 6, 6, "w"),
        (-1, 5, 5, "w"),
    ],
    "captain": [(-1, 5, 12, "w"), (0, 4, 13, "w"), (0, 8, 9, "y"), (1, 3, 14, "k")],
    "aviator": [
        (-1, 5, 12, "s"),
        (0, 4, 13, "s"),
        (1, 4, 6, "b"),
        (1, 11, 13, "b"),
        (1, 7, 10, "k"),
        (2, 3, 3, "s"),
        (3, 3, 3, "s"),
        (2, 14, 14, "s"),
        (3, 14, 14, "s"),
    ],
    "visor": [(4, 3, 14, "t"), (5, 4, 13, "t"), (4, 15, 15, "pk")],
    "retro": [
        (2, 3, 14, "pk"),
        (1, 15, 16, "pk"),
        (2, 16, 16, "pk"),
        (4, 4, 7, "k"),
        (4, 10, 13, "k"),
        (4, 8, 9, "k"),
    ],
    "explorer": [
        (-2, 7, 10, "s"),
        (-1, 5, 12, "s"),
        (0, 4, 13, "s"),
        (1, 2, 15, "s"),
        (0, 4, 13, "d", 2),
    ],
    "pirate": [
        (-1, 6, 11, "k"),
        (0, 4, 13, "k"),
        (1, 2, 15, "k"),
        (0, 8, 9, "w"),
        (3, 6, 10, "k"),
        (4, 11, 13, "k"),
        (5, 11, 13, "k"),
    ],
    "cowboy": [
        (-2, 6, 7, "s"),
        (-2, 10, 11, "s"),
        (-1, 5, 12, "s"),
        (0, 5, 12, "k"),
        (1, 1, 16, "s"),
    ],
    "chef": [
        (-3, 4, 13, "w"),
        (-2, 5, 12, "w"),
        (-1, 5, 12, "w"),
        (0, 5, 12, "w"),
        (1, 4, 13, "w"),
    ],
    "wizard": [
        (-3, 10, 11, "n"),
        (-2, 8, 11, "n"),
        (-1, 7, 11, "n"),
        (0, 6, 12, "n"),
        (1, 3, 14, "n"),
        (-1, 9, 9, "y"),
        (0, 7, 7, "y"),
    ],
    "viking": [
        (0, 5, 12, "d"),
        (1, 4, 13, "d"),
        (-2, 3, 3, "w"),
        (-2, 14, 14, "w"),
        (-1, 3, 4, "w"),
        (-1, 13, 14, "w"),
        (0, 4, 4, "w"),
        (0, 13, 13, "w"),
        (1, 8, 9, "y"),
    ],
    "tophat": [
        (-3, 6, 11, "k"),
        (-2, 6, 11, "k"),
        (-1, 6, 11, "r"),
        (0, 6, 11, "k"),
        (1, 4, 13, "k"),
    ],
    "flowers": [
        (1, 4, 13, "g"),
        (0, 5, 5, "r"),
        (0, 8, 9, "y"),
        (0, 12, 12, "pk"),
        (1, 6, 6, "w"),
        (1, 11, 11, "w"),
    ],
    "beret": [(-1, 8, 8, "r"), (0, 4, 12, "r"), (1, 3, 13, "r")],
    "grad": [
        (0, 2, 15, "k"),
        (1, 5, 12, "k"),
        (0, 8, 9, "y"),
        (1, 15, 15, "y"),
        (2, 15, 15, "y"),
        (3, 15, 15, "y"),
    ],
    "propeller": [
        (-2, 5, 12, "y"),
        (-1, 8, 9, "d"),
        (0, 6, 11, "r"),
        (1, 4, 13, "b"),
        (0, 8, 9, "y"),
    ],
    "shades": [
        (4, 4, 7, "k"),
        (4, 10, 13, "k"),
        (4, 8, 9, "k"),
        (5, 4, 6, "k"),
        (5, 11, 13, "k"),
    ],
}


def outfit_svg(spans: list[Span]) -> str:
    cells: dict[tuple[int, int], str] = {}
    for span in spans:
        y, x0, x1, color, *rest = span
        step = rest[0] if rest else 1
        for x in range(x0, x1 + 1, step):
            cells[(x, y + HAT_ROWS)] = color
    paths = []
    for color in dict.fromkeys(cells.values()):
        d = "".join(
            f"M{x} {y}h1v1h-1z"
            for (x, y), c in sorted(cells.items(), key=lambda i: (i[0][1], i[0][0]))
            if c == color
        )
        paths.append(f'<path fill="{PALETTE[color]}" d="{d}"/>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 {12 + HAT_ROWS}">{"".join(paths)}</svg>\n'


def main() -> None:
    for name, grid in FRAMES.items():
        assert all(len(row) == len(grid[0]) for row in grid), name
        (HERE / f"{name}.svg").write_text(svg(grid))
    for name, grid in FULL.items():
        assert len(grid) == 12 and all(len(row) == 18 for row in grid), name
        (HERE / f"{name}.svg").write_text(svg_grid(grid))
    for name, grid in PROPS.items():
        assert all(len(row) == len(grid[0]) for row in grid), name
        (HERE / f"{name}.svg").write_text(svg_grid(grid))
    outfits = HERE / "outfits"
    outfits.mkdir(exist_ok=True)
    for name, spans in OUTFITS.items():
        assert all(-HAT_ROWS < span[0] < 12 for span in spans), name
        (outfits / f"{name}.svg").write_text(outfit_svg(spans))


if __name__ == "__main__":
    main()
