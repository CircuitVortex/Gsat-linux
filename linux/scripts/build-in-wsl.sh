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
JOBS="$(nproc)"

export DEBIAN_FRONTEND=noninteractive

echo "== installing build dependencies"
apt-get update -qq
apt-get install -y --no-install-recommends \
    build-essential git bc bison flex libssl-dev libncurses-dev \
    unzip rsync wget cpio python3 file ca-certificates \
    qemu-system-arm >/dev/null

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
