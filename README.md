# GSAT MB86H615 reverse-engineering project

Working directory for analysis of the GSAT satellite receiver firmware
(`gsat_firm.bin`, 8 MiB, Fujitsu MB86H615 SoC) and for the headless Linux
build tree derived from it.

## Contents

```
gsat_firm.bin           original dump, exactly as read from the device (8 MiB)
gsat_firm.rev4.bin      word-swapped copy — for analysis only, never flash this
notes/
  00-triage.md          file facts, encoding, layout map, channel DB
  01-platform.md        SoC identification, why it is not Linux, feasibility
scripts/
  triage.py             entropy map, magic scan, string extraction
  deswap.py             transform search scored by readable-text yield
  anchor.py             known-plaintext proof of the byte-swap alignment
  normalize.py          produce gsat_firm.rev4.bin
  layout.py             fill map, architecture probes, hotspot strings
  identify.py           OS / SoC / crypto keyword scan + decompression probes
out/
  re_scan/              report.json, strings dumps, entropy.csv
linux/                  headless ARM1176 Linux build tree (Buildroot)
```

## Key facts

| | |
|---|---|
| Device | GSAT satellite receiver, Philippine channel lineup |
| SoC | Fujitsu **MB86H615**, ARM1176JZF-S (ARMv6) |
| Boot | `MB86H615 Flash Boot Loader` rev 5404 (2011-03-01), CRC slot scheme |
| Flash | 8 MiB, P/S/N-Flash capable, image stored **32-bit word-swapped** |
| Runtime | in-house RTOS + `FAPI_*` HAL, bget heap, OSD, DVB-S2 |
| Demod | Montage M88DS3103 |
| Front panel | FD650 I2C LED driver |
| Linux inside? | **No** — 0 ELF, 0 squashfs, 0 cpio, 0 compressed payloads |

## The byte-swap

Every 4-byte group in the dump is byte-reversed relative to the original image:

```
raw      )l32107654BA98FEDC      gubv niirpf:ftndab sab
rev4     (null)0123456789ABCDEF  bug in vfprintf: bad s...
```

`scripts/normalize.py` reverses it (offset 0, 4-byte groups). The 0x2C header is
authored in native order and is *not* part of the swap.

## Two separate goals

1. **Understand / modify this firmware** — notes and scripts above. Feasible
   today: decode the slot+CRC format, edit the channel database, rebuild a
   valid slot.
2. **Run Linux on the hardware** — `linux/`. Produces a genuine headless
   ARM1176 Linux image that boots under QEMU. It cannot boot on the receiver
   until the boot ROM format, DDR init and board pin definitions are known.
   See `linux/external/board/gsat-mb86h615/README.md`.

## Safety

- Keep `gsat_firm.bin` off-device and unmodified. It is the only recovery image.
- Writing `gsat_firm.rev4.bin` back to the device would brick it — the swap is
  an analysis transform only.
- Nothing in this repo has been written to the receiver.
