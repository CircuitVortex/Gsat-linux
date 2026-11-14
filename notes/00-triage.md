# gsat_firm.bin — triage notes

## File facts
- Size: 8,388,608 bytes (8 MiB = 0x800000)
- SHA-256 (as received): `B292484BE5A06D40AE6C85E9614AAA7389646EDDDEEF6D1487B9454E0F2B1E89`
- SHA-256 (rev4 normalized): `E1412B1618F92DC1A134C60AD37CD24536D0B7B4738557F82FBDE81BB18332DC`

## Encoding
Raw file is **32-bit word byte-swapped**. Reversing bytes in every 4-byte group
(from offset 0) restores readable text:

| raw | normalized |
|---|---|
| `)l32107654BA98FEDC` | `(null)0123456789ABCDEF` |
| ` gubv niirpf:ftndab sab ` | `bug in vfprintf: bad s...` |
| `BOLGT LATAEH1 RE` | `GLOBAL THEATRE 1` |
| `BOLGS LATROP` | `GLOBAL SPORT` |

Cause is most likely a dump/packaging step that emitted 32-bit words in the
opposite endianness of the device. Normalized image = `gsat_firm.rev4.bin`
(produced by `scripts/normalize.py`).

Note: the 0x2C-byte header is *not* readable under rev4 (`00 31 36 48`), so the
container header is authored in native order by the packer while the payload is
swapped.

## Identity — this is a GSAT satellite receiver (Philippines)
- Magic `H61\0` at 0x00, second tag `rTaC` at 0x20 (raw domain: `CaTr`)
- Channel names in the DB: `GLOBAL THEATRE 1..20 HD`, `GLOBAL SPORTS 5/6 HD`,
  `KNOWLEDGE CHANNEL`, `ONE MEDIA`, `ONE SPORTS`, `DepED TV / IBC 13`,
  `CNN PHILIPPINES`, `NATIONAL GEOGRAPHIC`, `HEALTH and WELLNESS`,
  `FM RADIO-LOVE RADIO`
- Domain vocabulary: DVB-S, PES/TS (`drv_tsd.c`, `No PES header workaround`),
  OSD, `MTRAPI_*` flash/GPIO API, `FD650` front-panel LED driver (I2C),
  `FAPI_INTR_RECEIVER_ARM` / `FAPI_INTR_RECEIVER_ARC` → dual-core SoC with an
  ARM host and an ARC co-processor in the demod path
- libc: newlib (`bug in vfprintf: bad base`, `(null)`, float NaN/INF tables)

## Layout (normalized image)
| range | size | content |
|---|---|---|
| 0x000000-0x00002C | 44 B | container header (magic, two version fields, two 0x400000 sizes, `rTaC`) |
| 0x00002C-0x071000 | 462 KB | high-ish entropy payload (5.55) — compressed/obfuscated blob |
| 0x071000-0x073000 | 8 KB | entropy 7.75 |
| 0x073000-0x090000 | 116 KB | mixed: strings, printf tables, drivers |
| 0x090000-0x108000 | 492 KB | entropy 7.95 (encrypted/compressed) |
| 0x109000-0x180000 | 488 KB | 0xFF fill |
| 0x180000-0x390000 | 2.1 MB | entropy 7.95 |
| 0x390000-0x510000 | 1.5 MB | 0xFF fill |
| 0x510000-0x6E7000 | 1.9 MB | mixed 6.9-7.7 + strings |
| 0x6E7000-0x740000 | 356 KB | 0xFF fill |
| 0x740000-0x750000 | 64 KB | `A5 5A` + 2bpp bitmap (`0x40`/`0x42`) = OSD font/graphics |
| 0x750000-0x800000 | 704 KB | sparse: channel DB text, duplicated blocks at 0x790000 and 0x7D0000 |

Bank A (0x000000-0x3FFFFF) vs bank B (0x400000-0x7FFFFF): only 12.5% bytes
equal, 110/1024 identical 4 KiB blocks → not a redundant A/B pair; bank B holds
a distinct payload (channel DB + graphics live there).

## Open questions
1. Is the 0x2C header checksummed/signed? (field at 0x24-0x2B is 0, `rTaC` tag)
2. Are the 7.95-entropy regions AES or a DVB-specific compression? Header
   suggests a single blob, not per-section framing.
3. `SCRAMBLE`/`Ca` strings near 0x740000 — channel DB may record encrypted
   service flags rather than firmware crypto.
4. CPU: ARM host confirmed by strings; need to confirm ARM vs Thumb and the
   load base before any disassembly is meaningful.

## Tooling
- `scripts/triage.py` — entropy map, magic scan, string dump
- `scripts/normalize.py` — word byte-swap normalization
- `scripts/deswap.py` — transform search/scoring
- `scripts/anchor.py` — known-plaintext alignment proof
- `scripts/layout.py` — fill map, arch probes, hotspot strings
