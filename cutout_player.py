from __future__ import annotations

from collections import deque
import math
import os
from PIL import Image


def _dist(c1: tuple[int, int, int], c2: tuple[int, int, int]) -> float:
    return math.sqrt(
        (c1[0] - c2[0]) ** 2 + (c1[1] - c2[1]) ** 2 + (c1[2] - c2[2]) ** 2
    )


def cutout(
    src: str,
    backup: str,
    out: str | None = None,
    threshold: float = 70.0,
) -> None:
    out = out or src

    im = Image.open(src).convert("RGBA")
    w, h = im.size
    px = im.load()

    if not os.path.exists(backup):
        Image.open(src).save(backup)

    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    bg = (
        sum(c[0] for c in corners) // 4,
        sum(c[1] for c in corners) // 4,
        sum(c[2] for c in corners) // 4,
    )

    visited = [[False] * h for _ in range(w)]
    q: deque[tuple[int, int]] = deque()

    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))

    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        if visited[x][y]:
            continue
        visited[x][y] = True

        r, g, b, a = px[x, y]
        ok = (a == 0) or (_dist((r, g, b), bg) <= threshold)
        if not ok:
            continue

        px[x, y] = (r, g, b, 0)
        q.append((x + 1, y))
        q.append((x - 1, y))
        q.append((x, y + 1))
        q.append((x, y - 1))

    im.save(out)
    print(f"cutout ok: out={out} backup={backup} bg={bg} threshold={threshold}")


if __name__ == "__main__":
    project_root = os.path.dirname(os.path.abspath(__file__))
    src_path = os.path.join(project_root, "player.png")
    backup_path = os.path.join(project_root, "player_original.png")
    cutout(src=src_path, backup=backup_path, out=src_path, threshold=70.0)

