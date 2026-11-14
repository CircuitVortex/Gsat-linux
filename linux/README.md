# GSAT MB86H615 — headless ARM1176 Linux

A minimal, terminal-only Linux for the **ARM1176JZF-S** core class, aimed at the
GSAT satellite receiver hardware (Fujitsu MB86H615). No X server, no Wayland, no
desktop: serial console + SSH, one pre-created account, and a build tree that is
reproducible.

> **Read this first.** The MB86H615 board support does not exist in this tree and
> cannot be derived from a firmware dump alone. This project builds a real Linux
> that runs under QEMU and is structured so the board half can be filled in when
> the hardware information exists. It will **not** boot on the receiver as-is.
> See `external/board/gsat-mb86h615/README.md` for the exact missing pieces.

## What you get

| Item | Value |
|---|---|
| Architecture | ARM1176JZF-S (ARMv6), soft-float ABI |
| Init | BusyBox init, no graphics stack |
| Console | `ttyAMA0` @ 115200 (serial only) |
| Remote access | Dropbear SSH on port 22, password auth |
| Account | `gsat-mb86h615` / `admin1231` (change with `passwd`) |
| Root | password `admin1231`, SSH login disabled |
| Rootfs | ext4, ~256 MB sparse image |
| Kernel | Linux 6.1.x, `versatile_defconfig` + fragment |

## Requirements

A Linux build host — WSL2 Ubuntu works. Buildroot does not build on Windows
natively.

```sh
sudo apt-get install -y build-essential git bc bison flex libssl-dev \
                        libncurses-dev unzip rsync wget cpio python3 \
                        qemu-system-arm
```

## Build

```sh
make            # clones Buildroot 2024.02.x into ./buildroot, then builds
```

Artifacts land in `output/images/`:

```
zImage            kernel
versatile-pb.dtb  device tree
rootfs.ext2       root filesystem
```

## Run (QEMU)

```sh
make run
# or
./scripts/qemu-run.sh
```

Log in on the console:

```
gsat-mb86h615 login: gsat-mb86h615
Password: admin1231
```

SSH from another terminal (host port 2222 → guest 22):

```sh
ssh -p 2222 gsat-mb86h615@127.0.0.1
```

Shut down cleanly with `poweroff` (or `Ctrl-A` then `X` to kill QEMU).

## Why this is the useful half of the port

Booting Linux on real hardware needs, in order:

1. an image the **mask ROM** will load (Fujitsu-proprietary header),
2. **DDR / PLL / pinmux / IRQ / timer** initialisation for the board,
3. drivers for OSD, video decoder, HDMI, TS demux, descrambler.

Steps 1–3 are board-specific and undocumented for MB86H615. Everything above
them — kernel config, userland, account, remote access, rootfs layout — is what
this tree provides, and it is identical whether the board is QEMU or silicon.

## Layout

```
Makefile                       build wrapper
scripts/qemu-run.sh            boot the image under QEMU (Linux/WSL)
scripts/qemu-run.ps1           same, on Windows with QEMU installed
external/Config.in             BR2_EXTERNAL entry point
external/external.mk
external/configs/gsat_headless_arm1176_defconfig
external/board/gsat-mb86h615/  users table, kernel fragment, post-build,
                               hardware checklist
```

## Rebuilding after a config change

```sh
make defconfig     # re-apply the defconfig
make menuconfig    # interactively, then `make savedefconfig`
make
```

To persist interactive changes back into the tree:

```sh
make -C buildroot O=$PWD/output BR2_EXTERNAL=$PWD/external savedefconfig
cp output/defconfig external/configs/gsat_headless_arm1176_defconfig
```
