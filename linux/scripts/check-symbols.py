#!/usr/bin/env python3
"""Check every symbol in a Buildroot defconfig actually exists in the Kconfig tree.

    python3 scripts/check-symbols.py <buildroot-dir> <defconfig>

Buildroot silently ignores unknown symbols in a defconfig (it warns, then builds
something subtly different than intended). This catches that before a 40-minute
build. It also flags symbols whose type looks wrong for the value given.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

DEF_RE = re.compile(r'^(BR2_[A-Z0-9_]+)\s*=\s*(.*)$')
CONFIG_RE = re.compile(r'^\s*(?:menu)?config\s+([A-Z0-9_]+)\s*$')
TYPE_RE = re.compile(r'^\s*(bool|tristate|string|int|hex)\b')


def parse_defconfig(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = DEF_RE.match(line)
        if m:
            out[m.group(1)] = m.group(2).strip('"')
    return out


def index_kconfig(root: Path) -> dict[str, list[tuple[str, int, str]]]:
    """name -> [(file, line, type-or-'')]"""
    idx: dict[str, list[tuple[str, int, str]]] = {}
    for p in root.rglob("Config.in*"):
        if not p.is_file():
            continue
        try:
            lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        cur: str | None = None
        for n, line in enumerate(lines, 1):
            m = CONFIG_RE.match(line)
            if m:
                cur = m.group(1)
                idx.setdefault(cur, []).append((str(p.relative_to(root)), n, ""))
                continue
            if cur:
                t = TYPE_RE.match(line)
                if t and not idx[cur][-1][2]:
                    f, ln, _ = idx[cur][-1]
                    idx[cur][-1] = (f, ln, t.group(1))
                    cur = None
    return idx


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    root = Path(sys.argv[1]).resolve()
    defconfig = Path(sys.argv[2]).resolve()

    symbols = parse_defconfig(defconfig)
    idx = index_kconfig(root)

    known, unknown = [], []
    for name, value in sorted(symbols.items()):
        (known if name in idx else unknown).append((name, value))

    print(f"buildroot : {root}")
    print(f"defconfig : {defconfig}")
    print(f"symbols   : {len(symbols)}  known={len(known)}  unknown={len(unknown)}")

    if unknown:
        print("\nUNKNOWN symbols (silently dropped by Buildroot):")
        for name, value in unknown:
            print(f"  {name}={value}")

    # type sanity for the ones we know
    print("\nresolved:")
    for name, value in known:
        types = sorted({t for _, _, t in idx[name] if t})
        t = ",".join(types) or "?"
        flag = ""
        if t in ("bool", "tristate") and value not in ("y", "n", "m"):
            flag = "  <-- value looks wrong for a bool"
        if t == "string" and value in ("y", "n"):
            flag = "  <-- string symbol given a boolean"
        loc = idx[name][0][0]
        print(f"  {name:<46} type={t:<8} {loc}{flag}")
    return 1 if unknown else 0


if __name__ == "__main__":
    raise SystemExit(main())
