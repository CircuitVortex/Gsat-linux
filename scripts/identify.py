#!/usr/bin/env python3
"""Identify OS / SoC / filesystem signatures and probe compressible blobs."""
import re, sys, zlib, lzma, io

PATH = sys.argv[1] if len(sys.argv) > 1 else "gsat_firm.rev4.bin"
d = open(PATH, "rb").read()

groups = {
    "OS / kernel": [b"Linux", b"linux", b"uC/OS", b"uCOS", b"eCos", b"ecos",
                    b"ThreadX", b"threadx", b"FreeRTOS", b"freertos", b"Nucleus",
                    b"VxWorks", b"vxworks", b"RTOS", b"kthread", b"init_task",
                    b"sys_call_table", b"do_exit", b"busybox", b"BusyBox",
                    b"proc/", b"dev/console", b"/bin/sh", b"ld-linux",
                    b"glibc", b"uClibc", b"musl", b"squashfs", b"JFFS2", b"cramfs",
                    b"ubifs", b"UBI#", b"mtd", b"MTD", b"ramdisk", b"initramfs"],
    "Bootloader": [b"U-Boot", b"u-boot", b"Das U-Boot", b"BootROM", b"bootrom",
                   b"bootcmd", b"bootargs", b"console=tty", b"tftp", b"TFTP"],
    "SoC / vendor": [b"NationalChip", b"GX6605", b"GX6621", b"GX66", b"Guoxin",
                     b"Hisilicon", b"Hi3716", b"Amlogic", b"Ali3", b"MStar",
                     b"Mstar", b"MONTAGE", b"Montage", b"M88", b"AVL", b"AV2018",
                     b"RDA58", b"FD650", b"ChipLink", b"MTRAPI", b"FAPI",
                     b"Sunplus", b"Novatek", b"Realtek", b"RTD", b"Amlogic",
                     b"AMLogic", b"Bestv", b"ZTE", b"SC9800", b"Sumavision"],
    "Crypto": [b"AES", b"aes_", b"DES", b"RSA", b"SHA256", b"sha256", b"HMAC",
               b"scramble", b"Scramble", b"SCRAMBLE", b"CAS", b"smartcard",
               b"SmartCard", b"Smart Card", b"key", b"Key", b"OTP", b"efuse",
               b"Crypto", b"crypt", b"Ctrl Word", b"ECM", b"EMM"],
    "DVB / tuner": [b"DVB", b"DVB-S", b"DVB-S2", b"DiSEqC", b"diseqc", b"LNB",
                    b"transponder", b"Transponder", b"TP ", b"symbol rate",
                    b"SymbolRate", b"FEC", b"QPSK", b"8PSK", b"Demod", b"demod",
                    b"Tuner", b"tuner", b"PES", b"PAT", b"PMT", b"SDT", b"NIT",
                    b"PCR", b"Viterbi", b"BlindScan", b"blindscan"],
}

print("== keyword hits (normalized image) ==")
for name, kws in groups.items():
    print(f"\n-- {name} --")
    for kw in kws:
        hits = []
        s = 0
        while True:
            i = d.find(kw, s)
            if i < 0:
                break
            hits.append(i)
            s = i + 1
            if len(hits) >= 6:
                break
        if hits:
            ctx = d[max(0, hits[0]-24):hits[0]+48]
            ctx = "".join(chr(c) if 32 <= c < 127 else "." for c in ctx)
            print(f"  {kw.decode('latin1'):18} {len(hits):>3} @ " +
                  ", ".join(f"0x{h:06X}" for h in hits[:4]) + f"   |{ctx}|")

print("\n\n== decompression probes on high-entropy regions ==")
regions = [(0x2C, 0x71000), (0x90000, 0x108000), (0x180000, 0x390000),
           (0x510000, 0x549000), (0x549000, 0x6E7000)]
for start, end in regions:
    found = []
    for off in range(start, min(start + 0x4000, end), 1):
        chunk = d[off:off+0x20000]
        # zlib / gzip
        for wbits, label in ((15, "zlib"), (31, "gzip"), (-15, "raw-deflate")):
            try:
                o = zlib.decompressobj(wbits)
                r = o.decompress(chunk, 0x10000)
                if len(r) > 256:
                    found.append((off, label, len(r), r[:40]))
            except Exception:
                pass
        try:
            r = lzma.decompress(chunk)
            if len(r) > 256:
                found.append((off, "lzma", len(r), r[:40]))
        except Exception:
            pass
    print(f"\nregion 0x{start:06X}-0x{end:06X}: {len(found)} decompressible streams")
    for off, lbl, n, head in found[:10]:
        print(f"  0x{off:06X} {lbl:12} out={n} head={head!r}")
