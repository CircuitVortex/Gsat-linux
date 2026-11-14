#!/usr/bin/env python3
"""Normalize gsat_firm.bin by byte-reversing every 4-byte group (offset 0)."""
import sys, hashlib

src = sys.argv[1] if len(sys.argv) > 1 else "gsat_firm.bin"
dst = sys.argv[2] if len(sys.argv) > 2 else "gsat_firm.rev4.bin"
d = open(src, "rb").read()
out = bytearray()
for i in range(0, len(d) - 3, 4):
    out += d[i:i+4][::-1]
out += d[len(out):]
open(dst, "wb").write(out)
print(f"{src} -> {dst} {len(out)} bytes")
print("sha256:", hashlib.sha256(out).hexdigest().upper())
