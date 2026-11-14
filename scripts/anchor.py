#!/usr/bin/env python3
"""Use known-plaintext anchors to determine the exact scrambling transform + alignment."""
import re, sys

PATH = sys.argv[1] if len(sys.argv) > 1 else r"gsat_firm.bin"
data = open(PATH, "rb").read()

target = b"0123456789ABCDEF"
variants = [target, target.lower(), b"0123456789abcdef",
            b"FEDCBA9876543210", b"FEDCBA9876543210".lower()]

for t in variants:
    i = data.find(t)
    if i >= 0:
        print(f"FOUND raw {t!r} at 0x{i:X}")

print("\n-- raw occurrences of mangled table patterns --")
for pat in (b"32107654", b"76543210", b"BA98FEDC", b"ba98fedc"):
    start = 0
    while True:
        i = data.find(pat, start)
        if i < 0:
            break
        lo = max(0, i - 24)
        print(f"0x{i:06X}  {data[lo:i+40].hex(' ')}")
        print(f"          {data[lo:i+40].decode('latin1')!r}")
        start = i + 1

def rev4(b, off):
    out = bytearray(b)
    for i in range(off, len(b) - 3, 4):
        out[i:i+4] = b[i:i+4][::-1]
    return bytes(out)

print("\n-- try rev4 at each alignment around those offsets --")
for i in [m.start() for m in re.finditer(rb"32107654", data)][:6]:
    for off in range(4):
        cand = rev4(data[max(0, i-64):i+64], (off - (i-64)) % 4 if i >= 64 else off)
        if b"0123456789ABCDEF" in cand or b"0123456789abcdef" in cand:
            print(f"hit at 0x{i:X} with file alignment {off}")

print("\n-- what a clean 32B window looks like under each transform (window at first hit) --")
i = data.find(b"32107654")
if i >= 0:
    base = i - 16
    win = data[base:base+80]
    print("raw   :", win.decode("latin1").replace("\x00", "."))
    for off in range(4):
        w = rev4(win, off)
        print(f"rev4@{off}:", w.decode("latin1").replace("\x00", "."))
    for g in (2, 8, 16):
        w = bytearray(win)
        for k in range(0, len(win), g):
            w[k:k+g] = win[k:k+g][::-1]
        print(f"rev{g}   :", bytes(w).decode("latin1").replace("\x00", "."))
