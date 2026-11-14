#!/usr/bin/env python3
"""Initial triage of gsat_firm.bin: entropy map, magic scan, strings, block structure."""
import math, sys, re, collections, os

PATH = sys.argv[1] if len(sys.argv) > 1 else r"gsat_firm.bin"
data = open(PATH, "rb").read()
print(f"file={PATH} size={len(data)} (0x{len(data):X})")

def ent(b):
    if not b:
        return 0.0
    c = collections.Counter(b)
    n = len(b)
    return -sum((v/n) * math.log2(v/n) for v in c.values())

BS = 4096
blocks = [(i, ent(data[i:i+BS])) for i in range(0, len(data), BS)]
print(f"blocks={len(blocks)} block_size={BS}")

# summarize entropy by grouping consecutive similar blocks
runs = []
for off, e in blocks:
    lvl = "H" if e > 7.5 else ("Z" if e < 0.5 else "M")
    if runs and runs[-1][0] == lvl:
        runs[-1][2] = off + BS
        runs[-1][3].append(e)
    else:
        runs.append([lvl, off, off + BS, [e]])
print("\n-- entropy runs --")
for lvl, s, e, es in runs:
    if e - s >= BS:  # show runs of at least 1 block
        print(f"{lvl} 0x{s:06X}-0x{e:06X}  {e-s:>9} bytes  avg_ent={sum(es)/len(es):.2f}")

print("\n-- magic scan --")
magics = {
    "gzip": b"\x1f\x8b\x08", "zlib": b"\x78\x9c", "xz": b"\xfd7zXZ\x00",
    "lzma": b"\x5d\x00\x00", "zstd": b"\x28\xb5\x2f\xfd", "lz4": b"\x04\x22\x4d\x18",
    "ELF": b"\x7fELF", "uboot_uimage": b"\x27\x05\x19\x56", "squashfs": b"hsqs",
    "cramfs": b"\x45\x3d\xcd\x28", "jffs2": b"\x85\x19", "Android_boot": b"ANDROID!",
    "tar": b"ustar", "zip": b"PK\x03\x04", "7z": b"7z\xbc\xaf\x27\x1c",
    "rar": b"Rar!\x1a\x07", "crypto_header_aes": b"Salted__",
}
for name, m in magics.items():
    hits = [i for i in range(len(data)) if data.startswith(m, i)][:20]
    if hits:
        print(f"{name:18} {len(hits)} hit(s): " + ", ".join(f"0x{h:X}" for h in hits[:8]))

print("\n-- repeated tags (H61, rTaC, and 4-byte patterns) --")
for tag in (b"H61\x00", b"rTaC", b"H61"):
    hits = []
    idx = data.find(tag)
    while idx != -1 and len(hits) < 40:
        hits.append(idx)
        idx = data.find(tag, idx + 1)
    print(f"{tag!r}: {len(hits)} -> " + ", ".join(f"0x{h:X}" for h in hits[:20]))

# find all 4-byte sequences at offset 0x20 region and any aligned repeats
print("\n-- bytes at candidate struct offsets --")
for off in (0x00, 0x20, 0x2C, 0x400000, 0x400020, 0x7FFFF0):
    if off < len(data):
        print(f"0x{off:06X}: {data[off:off+48].hex(' ')}")

print("\n-- ASCII strings (>=8 chars) sample --")
s = re.findall(rb"[\x20-\x7E]{8,}", data)
print(f"total strings={len(s)}")
cnt = collections.Counter(s)
for v, c in cnt.most_common(60):
    print(f"  {c:>4}x {v[:100].decode('latin1')}")
print("\n-- first 80 dates/versions-looking strings --")
pat = re.compile(rb"(?:v?\d+\.\d+\.\d+[-A-Za-z0-9_.]*)|(?:20\d\d-\d\d-\d\d)|(?:[A-Z][A-Z0-9_]{6,})")
seen = []
for m in pat.finditer(data[:len(data)]):
    t = m.group().decode("latin1")
    if t not in seen:
        seen.append(t)
    if len(seen) >= 80:
        break
print(" ".join(seen))
