#!/bin/bash
# Build the GSAT headless image inside WSL.
#
# Buildroot on /mnt/c is slow and fights DrvFs over permissions/symlinks, so the
# tree is copied to the WSL native filesystem, built there, and only the images
# are copied back.
#
# Usage (from PowerShell):
#   wsl -d Ubuntu-24.04 -u root -- bash "/mnt/c/Users/<you>/Desktop/Reverse/linux/scripts/build-in-wsl.sh"
set -euo pipefail

SRC="/mnt/c/Users/Xerxes Robb Arsolon/Desktop/Reverse/linux"
WORK="${WORK:-$HOME/gsat-linux-build}"
JOBS="${JOBS:-$(nproc)}"

export DEBIAN_FRONTEND=noninteractive
# The imported distro runs as root, and some host packages (GNU tar first)
# abort in configure when invoked as root. Buildroot and its CI accept root
# builds; this is the documented override.
export FORCE_UNSAFE_CONFIGURE=1

echo "== installing build dependencies"
apt-get update -qq
# e2fsprogs provides mke2fs, which Buildroot uses to build rootfs.ext2.
# qemu-system-arm is only needed to boot-test the result: INSTALL_QEMU=1.
PKGS="build-essential git bc bison flex libssl-dev libncurses-dev
      unzip rsync wget cpio python3 file ca-certificates
      perl patch gawk bzip2 xz-utils which tar gzip sed findutils
      e2fsprogs dosfstools"
if [ "${INSTALL_QEMU:-0}" = "1" ]; then
    PKGS="$PKGS qemu-system-arm"
fi
# shellcheck disable=SC2086
apt-get install -y --no-install-recommends $PKGS >/dev/null

echo "== staging source in $WORK"
mkdir -p "$WORK"
rsync -a --delete --exclude 'output' --exclude 'buildroot' "$SRC"/ "$WORK"/

cd "$WORK"

echo "== buildroot clone + defconfig"
make buildroot defconfig

echo "== building (-j$JOBS)"
make -j"$JOBS" build

echo "== collecting artifacts"
mkdir -p "$SRC/output/images"
for f in zImage versatile-pb.dtb rootfs.ext2; do
    if [ -f "output/images/$f" ]; then
        cp -f "output/images/$f" "$SRC/output/images/"
    else
        echo "WARNING: output/images/$f missing" >&2
    fi
done

ls -lh "$SRC/output/images/"
echo "== done"
