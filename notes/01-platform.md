# 01 — Platform identification: what this firmware actually is

## Verdict
`gsat_firm.bin` is **not Linux**, and cannot be turned into Linux by reversing it.
It is a Fujitsu bare-metal / small-RTOS set-top-box application.

## Hard evidence
### Boot loader
```
===========================================
MB86H615 Flash Boot Loader - $Revision: 5404 $
$Date: 2011-03-01 13:47:50 +0100 (Tue, 01 Mar 2011) $
(C) Copyright 2006-2010 by Fujitsu Microelectronics Europe GmbH
(C) Copyright 2010-2011 by Fujitsu Semiconductor Europe GmbH
```
Boot flow strings:
```
Searching valid slot on P-Flash / S-Flash / N-Flash
Found valid slot at adress 0x%08x
Start CRC check for the slot...
Booting from Slot 0...
Try Booting from Slot %d...
Image copy failed: %i
Application bad, start loader!
Hardware Version: 0x%04X
Build: %s %s Version: %s-%s
```
→ slot-based, CRC-validated boot from parallel NOR (P-Flash), serial NOR
(S-Flash) or NAND (N-Flash). Header magic `H61\0` at 0x00 = SoC family
(MB86H**61**), consistent with the boot loader banner.

### CPU core
```
ARM1176_INTR_FiqFunction / AbortFunction / PrefetchFunction /
UndefFunction / SwiFunction
got SWI parameter 0x%08x
going to POLLING mode / going to HALT mode
```
→ **ARM1176JZF-S** (ARMv6, has MMU). Same core family as BCM2835 (RPi 1),
so mainline Linux *does* support the core — the blockers are board-level.

### Kernel / runtime (in-house, not Linux)
```
RTOS_SHARED_MODULE_BASE
RTOS_ERR_NOT_INITIALISED
mmu/src/drv_mmu_heap_bget.c
b->bh.bsize > 0 / b->bh.bsize < 0        <- bget heap allocator asserts
ERROR: thread specific print buffer overflow (%u>%u), exiting...
ERROR: "%s" driver initialization failed. (err=%d)
```
→ small RTOS with MMU driver, per-thread printf buffer, bget allocator.

### Peripherals
| Component | Evidence |
|---|---|
| DVB-S2 demod | `FUJITSU_W9_YINHE_2212_M88DS3103_ZSCD_YNGQ` → **Montage M88DS3103** |
| Front panel | `MTR_FP_SCAN_MCU_FD650_MODE`, `[FD650_SCL]`, `[FD650_SDA]` → FD650 I2C LED driver |
| OSD | `Initializing OSD...`, `OSDHANDLER_StartLayer OSD1`, `No support bmp format` |
| Video | `Initializing VIDEO...`, `VAL_Init/GoUp` |
| HDMI | `FAPI_HDMI_ERR_HDCP_MAX_CASCADE_EXCEEDED`, `..._SHA_1_MISMATCH` |
| Demux / TS | `FAPI_TSD_ERR_PES_PARSER_COUNT_EXEEDED`, `drv_tsd.c`, `PES header workaround` |
| Descrambler | `FAPI_DESC_MODULE_BASE`, `FAPI_DESC_ERR_BAD_PARAMETER` |
| Crypto | AES/DES/SHA in FAPI |
| I2C/GPIO/Flash | `MTRAPI_Flash_*`, `FAPI_I2C_SOFTWARE/HARDWARE` |

## Negative results (no Linux anywhere)
Scanned whole image under all 4 transforms (`out/re_scan/report.json`):

| object | hits |
|---|---|
| ELF | **0** |
| squashfs (le/be) | 0 |
| cpio (newc/crc) | 0 |
| gzip / xz / bzip2 / lz4 / zstd | 0 |
| UBI / U-Boot / uImage / DTB | 0 |
| cramfs | 0 |
| Android boot | 0 |

The 242 raw "magic hits" are 2-byte coincidences (62 `jffs2` = `0x8519`,
5 `jpeg` = `0xFFD8FF`) — expected density in 8 MiB of random data, not real
filesystems.

Also absent: `bootargs`, `console=tty`, `/bin/sh`, `busybox`, `glibc`,
`uClibc`, `musl`, MTD, UBI.

**Consequence:** `Desktop/BP-OJBS/gsat/gsat_linux.py` builds a Docker image
that unsquashes payloads and runs carved ELF objects under `qemu-user`. Both
inputs are empty on this image, so that pipeline cannot produce anything.

## Why a Linux port is not viable here
1. **Boot ROM is mask ROM.** The image's boot loader is the *secondary* loader.
   The primary loader in silicon expects a Fujitsu-proprietary image header.
   That format is not public; you cannot place a U-Boot/kernel where the chip
   will read it.
2. **Undocumented board init.** DDR/PLL/pinmux/interrupt controller/timer
   registers must be known to write a board file. No datasheet: MB86H6x is
   NDA'd and Fujitsu exited the STB SoC business.
3. **No drivers for the parts that matter.** OSD, video decoder, HDMI, TS
   demux, descrambler and smartcard interface are proprietary. Without them
   Linux would boot to a serial console and nothing else — no picture, no tuner.
4. **No payload budget.** 8 MiB of flash total, much of it already allocated.
   Kernel + initramfs would fit only in the most stripped configuration, with
   nowhere to put a userland.
5. **No reference design.** No public MB86H6x Linux BSP exists to start from.

Effort if attempted anyway: person-months to years, needing hardware, a JTAG
probe, and silicon documentation — with a real chance of bricking the box.

## What is achievable instead
- **A. Modify this firmware** — decode the slot/CRC format, then edit the
  channel DB / OSD resources / settings and rebuild an image the boot loader
  will still accept. Realistic.
- **B. Emulate it** — a QEMU machine model for MB86H615 + peripherals. Very
  hard without docs; only useful to run the original firmware on a PC.
- **C. Use hardware that already runs Linux** — Enigma2/OpenPLi boxes
  (Zgemma, Octagon, Vu+) or a GX6605-based box with OpenPLi/Neutrino.
- **D. Hunt for a leaked MB86H60/H61 Linux BSP** — would change the calculus
  but still needs boards and datasheets.
