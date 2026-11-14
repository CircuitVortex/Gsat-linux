#!/usr/bin/env python3
"""Map fill regions, alignment, and probe CPU architecture of gsat_firm.rev4.bin."""
import sys, collections, re

PATH = sys.argv[1] if len(sys.argv) > 1 else "gsat_firm.rev4.bin"
data = open(PATH, "rb").read()
N = len(data)

def classify(b):
    if not b:
        return "empty"
    c = collections.Counter(b)
    top, cnt = c.most_common(1)[0]
    if cnt == len(b):
        return f"fill(0x{top:02X})"
    return "data"

BS = 0x1000
print("== fill map (1 KiB blocks) ==")
runs = []
for off in range(0, N, BS):
    t = classify(data[off:off+BS])
    if runs and runs[-1][0] == t:
        runs[-1][2] = off + BS
    else:
        runs.append([t, off, off + BS])
for t, s, e in runs:
    if e - s >= BS * 4 or "fill" in t:
        print(f"{t:12} 0x{s:06X}-0x{e:06X}  {e-s:>9}")

print("\n== architecture probes ==")
mips_epilogue = len(re.findall(rb"\x27\xbd", data))     # addiu sp,sp,imm
mips_jr_ra = len(re.findall(rb"\x03\xe0\x00\x08", data))
arm_push_lr = len(re.findall(rb"[\x00-\xff]{2}\x2d\xe9", data))
thumb_push = len(re.findall(rb"[\x00-\xff]\xb5", data))
print(f"MIPS 'addiu sp,sp' (27 bd): {mips_epilogue}")
print(f"MIPS 'jr ra' (03 e0 00 08): {mips_jr_ra}")
print(f"ARM  'push {{..lr}}' (xx xx 2d e9): {arm_push_lr}")
print(f"Thumb 'push {{lr}}' (xx b5): {thumb_push}")

print("\n== printable-string hotspots by 64 KiB page ==")
pages = collections.Counter()
for m in re.finditer(rb"[ -~]{10,}", data):
    pages[m.start() // 0x10000] += 1
for p, c in pages.most_common(15):
    print(f"page 0x{p*0x10000:06X}  strings(>=10)={c}")

print("\n== longest strings per hotspot ==")
for p, _ in pages.most_common(6):
    lo, hi = p * 0x10000, min(N, (p + 1) * 0x10000)
    ss = sorted(re.findall(rb"[ -~]{8,}", data[lo:hi]), key=len, reverse=True)[:8]
    print(f"-- page 0x{lo:06X}")
    for s in ss:
        print("   ", s[:120].decode("latin1"))

print("\n== hexdump 0x740000 ==")
base = 0x740000
for i in range(base, base + 0x180, 16):
    b = data[i:i+16]
    print(f"{i:06x}  {b.hex(' ')}  {''.join(chr(x) if 32 <= x < 127 else '.' for x in b)}")
