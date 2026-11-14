#!/bin/bash
# Verify the built image without booting it.
#
#   ./scripts/verify-image.sh [output/images/rootfs.ext2]
#
# Reads the ext4 image with debugfs (no root, no loop mount) and asserts the
# headless contract: account, password hash, serial getty, ssh, no desktop.
set -uo pipefail

IMG="${1:-output/images/rootfs.ext2}"
IMGDIR="$(dirname "$IMG")"
KERNEL="${KERNEL:-$IMGDIR/zImage}"
DTB="${DTB:-$IMGDIR/versatile-pb.dtb}"

pass=0
fail=0
ok()   { printf '  [ ok ] %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }
skip() { printf '  [ .. ] %s\n' "$1"; }

need_file() {
    if [ -f "$1" ]; then ok "$2 ($(du -h "$1" | cut -f1))"; else bad "$2 missing: $1"; fi
}

echo "== artifacts"
need_file "$KERNEL" "kernel zImage"
need_file "$DTB"    "device tree versatile-pb.dtb"
need_file "$IMG"    "root filesystem"

# extract a file from the image
rd() { debugfs -R "cat $1" "$IMG" 2>/dev/null; }

echo "== kernel"
if [ -f "$KERNEL" ]; then
    desc=$(file -b "$KERNEL")
    case "$desc" in
        *ARM*) ok "kernel is ARM: ${desc%%,*}" ;;
        *)     bad "kernel is not ARM: $desc" ;;
    esac
fi

echo "== account"
if pw=$(rd /etc/passwd) && printf '%s' "$pw" | grep -q '^gsat-mb86h615:'; then
    line=$(printf '%s\n' "$pw" | grep '^gsat-mb86h615:')
    uid=$(printf '%s' "$line" | cut -d: -f3)
    home=$(printf '%s' "$line" | cut -d: -f6)
    shell=$(printf '%s' "$line" | cut -d: -f7)
    ok "user gsat-mb86h615 present (uid=$uid home=$home shell=$shell)"
else
    bad "user gsat-mb86h615 not in /etc/passwd"
fi

if sh=$(rd /etc/shadow) && printf '%s' "$sh" | grep -q '^gsat-mb86h615:'; then
    h=$(printf '%s\n' "$sh" | awk -F: '/^gsat-mb86h615:/{print $2}')
    case "$h" in
        ''|'!'*|'*') bad "password for gsat-mb86h615 is blank or locked (hash='$h')" ;;
        \$1\$*|\$5\$*|\$6\$*|\$y\$*) ok "password hash set (${h%%\$*}crypt)" ;;
        *)           bad "password is not a crypt hash - login impossible (got '$h')" ;;
    esac
else
    bad "user gsat-mb86h615 has no /etc/shadow entry - login impossible"
fi

if rd /etc/passwd | grep -q '^root:'; then
    rh=$(rd /etc/shadow | awk -F: '/^root:/{print $2}')
    case "$rh" in
        ''|'!'*|'*') ok "root login locked" ;;
        *)           ok "root has a password (console/su only)" ;;
    esac
fi

echo "== console"
if ib=$(rd /etc/inittab) && printf '%s\n' "$ib" | grep -qE '^ttyAMA0::respawn:/sbin/getty .*ttyAMA0 115200'; then
    ok "serial getty on ttyAMA0 at 115200: $(printf '%s\n' "$ib" | grep ttyAMA0 | head -1)"
else
    bad "no respawning 115200 getty on ttyAMA0 in /etc/inittab"
fi

echo "== ssh"
if rd /etc/passwd | grep -q 'dropbear'; then ok "dropbear service account created"; else skip "no dropbear user"; fi
db=$(debugfs -R "ls -l /usr/sbin" "$IMG" 2>/dev/null | grep -c dropbear)
db2=$(debugfs -R "ls -l /usr/bin" "$IMG" 2>/dev/null | grep -c dropbear)
if [ $((db + db2)) -gt 0 ]; then ok "dropbear binary installed"; else bad "dropbear binary not found"; fi
if rd /etc/default/dropbear | grep -q -- '-w'; then ok "ssh denies root login (-w)"; else skip "no dropbear args override"; fi

echo "== headless"
if rd /etc/motd | grep -qi 'GSAT'; then ok "GSAT motd installed"; else skip "motd not branded"; fi
ub=$(debugfs -R "ls -l /usr/bin" "$IMG" 2>/dev/null)
if [ -z "$ub" ]; then
    bad "could not list /usr/bin - debugfs read failed, so 'no graphics' is unproven"
else
    x=$(printf '%s\n' "$ub" | grep -cE ' Xorg| Xvfb')
    w=$(printf '%s\n' "$ub" | grep -c wayland)
    lib=$(debugfs -R "ls -l /usr/lib" "$IMG" 2>/dev/null | grep -cE 'libX11|libwayland')
    if [ "$x" -eq 0 ] && [ "$w" -eq 0 ] && [ "$lib" -eq 0 ]; then
        ok "no X11 / Wayland binaries or libraries"
    else
        bad "graphics stack present (X=$x wayland=$w libs=$lib)"
    fi
fi

echo
echo "== summary: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
