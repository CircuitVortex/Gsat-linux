# Project status — paused (2026-11-14)

State of the GSAT MB86H615 work, written so it can be resumed cold.

## What is finished

**Firmware analysis** (`notes/`, `scripts/`)
- `gsat_firm.bin` is a 32-bit word byte-swapped image (`H61\0` + `rTaC`), 8 MiB.
- Platform: Fujitsu MB86H615 (ARM1176JZF-S), Montage M88DS3103 demod, FD650 panel.
- Proven **no Linux inside**: 0 ELF, 0 squashfs, 0 cpio, 0 gzip/xz, 0 U-Boot/DTB.
- Channel DB recovered (GLOBAL THEATRE 1–20 HD, CNN PHILIPPINES, DepEd TV, IBC 13, …).
- `gsat_firm.rev4.bin` is normalised for **analysis only — do not flash**.

**Linux build tree** (`linux/`)
- Buildroot 2024.02.x external tree, ARM1176, uClibc-ng, terminal only.
- Account `gsat-mb86h615` / `admin1231`, serial getty on `ttyAMA0` @ 115200,
  dropbear SSH, no X11.
- Verification: `linux/scripts/verify-image.sh`, boot test:
  `linux/scripts/boot-test-wsl1.sh`.

**CI** — `.github/workflows/build-gsat-linux.yml`
- Repo: https://github.com/CircuitVortex/Gsat-linux (public)
- Builds, verifies, boots in QEMU, uploads `gsat-images`.

## Last known CI state

| Run | Commit | Result | Meaning |
|---|---|---|---|
| 43594138803 | 4b73c04 | **failure** | compiled fully; died in `target-finalize` on our post-build hook |
| 43596549716 | 8e91af6 | **cancelled by choice** | would have been the first green run |

Fixes in `8e91af6`, **not yet proven by a green run**:
1. `/etc/dropbear` is a dangling symlink created by `dropbear.mk:135`;
   `mkdir -p` on it fails with `EEXIST`. The hook no longer touches it.
2. getty baudrate defaulted to `0` ("keep kernel default"); now explicitly
   `BR2_TARGET_GENERIC_GETTY_BAUDRATE_115200=y`.

Untested gates remaining: `verify image contents` and `smoke boot`.

## How to resume

```powershell
cd "C:\Users\Xerxes Robb Arsolon\Desktop\Reverse"
gh auth status                     # must be logged in as CircuitVortex
gh run rerun 43596549716 --repo CircuitVortex/Gsat-linux    # or:
git commit --allow-empty -m "retry build"; git push
```

Then, when green:

```powershell
gh run download <run-id> -n gsat-images -D .   # lands in linux/output/images
```

Local alternative (WSL1, no virtualization, ~4–7 h on the HDD):
```powershell
wsl -d Ubuntu-24.04-Build -- bash -lc 'JOBS=3 bash "/mnt/c/Users/Xerxes Robb Arsolon/Desktop/Reverse/linux/scripts/build-in-wsl.sh"'
```
The previous local build tree was deleted to reclaim 762 MB; this rebuilds it.

## Known risk not yet disproven

`qemu-run.sh` and the CI smoke boot pass `-dtb versatile-pb.dtb`. Buildroot's own
versatilepb recipe relies on ATAGs instead. If the boot reaches no login prompt,
delete the `-dtb` line first — that is the cheapest experiment.

## Hard limit, stated plainly

This image **cannot be flashed to the actual receiver**. No boot ROM entry
point, no DDR init, no UART base, and the flash expects the `H61\0`/`rTaC`
slot+CRC container. Anything written to the device risks bricking it; the 8 MiB
dump is the only recovery image.

## Machine notes (this PC)

- WSL2 impossible: SVM disabled in firmware, BIOS changes declined.
- Local builds run in **WSL1** (`Ubuntu-24.04-Build`), which needs no VM.
- `/etc/wsl.conf` sets `interop.appendWindowsPath = false` — Buildroot rejects
  a `PATH` containing spaces.
- Root builds need `FORCE_UNSAFE_CONFIGURE=1` (exported by `build-in-wsl.sh`).
- Do not update BIOS. Do not flash the receiver.
