#!/bin/sh
# Boot the built image under QEMU (system-arm, Versatile PB, ARM1176 core).
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
IMG="$HERE/output/images"

for f in zImage versatile-pb.dtb rootfs.ext2; do
    [ -f "$IMG/$f" ] || { echo "missing $IMG/$f — run 'make' first" >&2; exit 1; }
done

QEMU=${QEMU:-qemu-system-arm}
command -v "$QEMU" >/dev/null 2>&1 || {
    echo "qemu-system-arm not found. Install it (apt install qemu-system-arm)" >&2
    exit 1
}

# ARM1176JZF-S core so the ARMv6 userland matches. If your QEMU refuses the
# cpu/machine combination, drop the -cpu line; the kernel still boots, but
# userland built for ARMv6 may SIGILL on an ARMv5 core.
CPU_ARGS="-cpu arm1176"

exec "$QEMU" \
    -M versatilepb $CPU_ARGS \
    -m 256M \
    -kernel "$IMG/zImage" \
    -dtb "$IMG/versatile-pb.dtb" \
    -drive file="$IMG/rootfs.ext2",if=scsi,format=raw \
    -append "rootwait root=/dev/sda rw console=ttyAMA0,115200" \
    -net nic,model=rtl8139 -net user,hostfwd=tcp::2222-:22 \
    -nographic
