#!/usr/bin/env python3
"""Test candidate byte-scramblings on gsat_firm.bin and score by printable-string quality."""
import re, sys, collections

PATH = sys.argv[1] if len(sys.argv) > 1 else r"gsat_firm.bin"
data = open(PATH, "rb").read()

def deswap(b, g):
    out = bytearray(len(b))
    for i in range(0, len(b), g):
        chunk = b[i:i+g]
        out[i:i+len(chunk)] = chunk[::-1]
    return bytes(out)

def bitrev(b):
    return bytes(int(f"{x:08b}"[::-1], 2) for x in b)

cands = {"none": data}
for g in (2, 4, 8, 16):
    for off in range(g):
        cands[f"rev{g}@+{off}"] = data[:off] + deswap(data[off:], g)
cands["bitrev"] = bitrev(data)

def score(b):
    s = re.findall(rb"[ -~]{8,}", b)
    good = [x for x in s if len(re.findall(rb"[a-z]{3}", x)) >= 3]
    letters = sum(1 for c in b if 97 <= c <= 122 or 65 <= c <= 90)
    # english-ish score: proportion of 3+ letter runs
    return len(good), letters / max(1, len(b)), len(s)

rows = sorted(((score(v), k) for k, v in cands.items()), reverse=True)
print("score(goodstrings, letterratio, totalstrings)  transform")
for sc, name in rows[:12]:
    print(f"{sc}  {name}")

best = rows[0][1]
print(f"\n=== best: {best} ===")
b = cands[best]
s = sorted(set(re.findall(rb"[ -~]{8,}", b)))
print(f"unique strings: {len(s)}")
for x in s[:150]:
    print("  ", x[:110].decode("latin1"))
