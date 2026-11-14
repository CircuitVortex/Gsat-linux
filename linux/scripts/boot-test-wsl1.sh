#!/bin/bash
# Boot-test the built image under QEMU: pass only if a login prompt appears.
#
# Non-interactive counterpart to qemu-run.sh. It boots the image headless,
# captures the complete serial console to a log, waits for Buildroot's getty
# prompt, then kills QEMU. Written for WSL1, which exposes no /dev/kvm: QEMU
# falls back to TCG software emulation, and a cold boot of a 2024 kernel on a
# spinning disk can take several minutes -- hence the generous default timeout.
#
# Usage (works from any cwd; the default image dir is relative to this script):
#   bash scripts/boot-test-wsl1.sh [image-dir] [timeout-seconds]
#
#   image-dir        default ../output/images
#   timeout-seconds  default 900, must be a positive integer
#
# Environment:
#   QEMU      QEMU binary                      (default qemu-system-arm)
#   SSH_PORT  host port forwarded to guest 22  (default 2222)
#   LOG       serial console log               (default ${TMPDIR:-/tmp}/boot-test-<pid>.log)
#
# Exit status: 0 login prompt reached; 1 boot failed or timed out;
#              2 bad arguments or missing prerequisites.
set -euo pipefail

# C locale: predictable [[:space:]] matching and grep text handling.
export LC_ALL=C

usage() {
    cat <<'EOF'
usage: boot-test-wsl1.sh [image-dir] [timeout-seconds]

  image-dir        directory with zImage, versatile-pb.dtb, rootfs.ext2
                   (default ../output/images next to this script)
  timeout-seconds  seconds to wait for a login prompt (default 900)

environment: QEMU=<binary> SSH_PORT=<host port for guest 22> LOG=<serial log>
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac
if [ "$#" -gt 2 ]; then
    usage >&2
    exit 2
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
IMG_DIR=${1:-"$SCRIPT_DIR/../output/images"}
TIMEOUT=${2:-900}
SSH_PORT=${SSH_PORT:-2222}
QEMU=${QEMU:-qemu-system-arm}
LOG=${LOG:-"${TMPDIR:-/tmp}/boot-test-$$.log"}
QEMU_ERR="$LOG.qemu"

case "$TIMEOUT" in
    ''|*[!0-9]*)
        echo "error: timeout must be a whole number of seconds (got '$TIMEOUT')" >&2
        exit 2
        ;;
esac
case "$SSH_PORT" in
    ''|*[!0-9]*)
        echo "error: SSH_PORT must be a whole number (got '$SSH_PORT')" >&2
        exit 2
        ;;
esac

# $((...)) reads a leading zero as octal ("0900" is a syntax error), so force
# base 10 before either value is used in arithmetic or in the hostfwd string.
TIMEOUT=$((10#$TIMEOUT))
SSH_PORT=$((10#$SSH_PORT))

[ "$TIMEOUT" -ge 1 ] || { echo "error: timeout must be at least 1 second" >&2; exit 2; }
if [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    echo "error: SSH_PORT must be between 1 and 65535" >&2
    exit 2
fi

if [ ! -d "$IMG_DIR" ]; then
    echo "error: image directory does not exist: $IMG_DIR" >&2
    echo "       run 'make build' or pass the directory as the first argument" >&2
    exit 2
fi

echo "== boot test"
printf '  image dir: %s\n' "$IMG_DIR"
printf '  timeout  : %ss\n' "$TIMEOUT"

# ---- preflight ----------------------------------------------------------
preflight=0
for f in zImage versatile-pb.dtb rootfs.ext2; do
    if [ -s "$IMG_DIR/$f" ]; then
        printf '  [ ok ] %-18s %s\n' "$f" "$(du -h "$IMG_DIR/$f" | cut -f1)"
    else
        printf '  [FAIL] %-18s missing or empty: %s\n' "$f" "$IMG_DIR/$f" >&2
        preflight=1
    fi
done
[ "$preflight" -eq 0 ] || {
    echo "hint: run 'make build', or pass the images directory as the first argument" >&2
    exit 2
}

QEMU_BIN=$(command -v "$QEMU" 2>/dev/null || true)
if [ -z "$QEMU_BIN" ]; then
    cat >&2 <<'EOF'
  [FAIL] qemu-system-arm is not installed, so the image cannot be boot-tested.
         WSL1 has no KVM, but TCG emulation is sufficient. Install it with:
           sudo apt-get update && sudo apt-get install -y qemu-system-arm
EOF
    exit 2
fi
printf '  [ ok ] %-18s %s\n' "qemu" "$QEMU_BIN"

LOG_DIR=$(dirname "$LOG")
if ! mkdir -p "$LOG_DIR" 2>/dev/null || ! : >"$LOG" || ! : >"$QEMU_ERR"; then
    echo "error: cannot create or write the log files at $LOG" >&2
    exit 2
fi

NET_ARGS=(-net nic,model=rtl8139)
# If something already listens on the host port, QEMU's hostfwd would fail to
# bind and abort the boot. Skip the forward instead; login does not need SSH.
# bash's /dev/tcp gives a cheap localhost probe (a successful connect = busy).
if (exec 3<>"/dev/tcp/127.0.0.1/$SSH_PORT") 2>/dev/null; then
    printf '  [ .. ] %-18s host port %s busy, forward disabled\n' "ssh" "$SSH_PORT"
    NET_ARGS+=(-net user)
else
    NET_ARGS+=(-net "user,hostfwd=tcp::${SSH_PORT}-:22")
    printf '  [ ok ] %-18s host %s -> guest 22\n' "ssh" "$SSH_PORT"
fi

# ---- QEMU lifecycle -----------------------------------------------------
QEMU_PID=""
STOPPING=""

# kill -0 also succeeds for a child that exited but has not been reaped yet, so
# consult /proc as well and treat a zombie (state Z) as already dead.
process_alive() {
    kill -0 "$1" 2>/dev/null || return 1
    if [ -r "/proc/$1/status" ] &&
       grep -q '^State:[[:space:]]*Z' "/proc/$1/status" 2>/dev/null; then
        return 1
    fi
    return 0
}

# Kill and reap QEMU. Runs from the EXIT trap on every path (success, failure,
# Ctrl-C, TERM), so no orphan QEMU is left behind. Idempotent.
stop_qemu() {
    [ -z "$STOPPING" ] || return 0
    STOPPING=1
    if [ -n "$QEMU_PID" ]; then
        if process_alive "$QEMU_PID"; then
            kill -TERM "$QEMU_PID" 2>/dev/null || true
            n=0
            # Give QEMU a moment to exit cleanly, then insist.
            while process_alive "$QEMU_PID" && [ "$n" -lt 5 ]; do
                sleep 1
                n=$((n + 1))
            done
            if process_alive "$QEMU_PID"; then
                kill -KILL "$QEMU_PID" 2>/dev/null || true
            fi
        fi
        wait "$QEMU_PID" 2>/dev/null || true
        QEMU_PID=""
    fi
    return 0
}
trap stop_qemu EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# Serial goes only to the log: -serial file:... suppresses the default serial
# device, and -monitor none suppresses the monitor, so -nographic adds no
# mon:stdio chardev and nothing reads the terminal. stdin is /dev/null so an
# unattended run can never block on input.
#
# -snapshot gives the drive a throwaway copy-on-write overlay, so a boot test
# never modifies the built rootfs.ext2.
#
# -accel tcg is explicit because WSL1 exposes no /dev/kvm.
"$QEMU_BIN" \
    -M versatilepb \
    -cpu arm1176 \
    -m 256M \
    -accel tcg \
    -kernel "$IMG_DIR/zImage" \
    -dtb "$IMG_DIR/versatile-pb.dtb" \
    -drive "file=$IMG_DIR/rootfs.ext2,if=scsi,format=raw" \
    -append "rootwait root=/dev/sda rw console=ttyAMA0,115200" \
    "${NET_ARGS[@]}" \
    -snapshot \
    -nographic \
    -monitor none \
    -serial "file:$LOG" \
    </dev/null >/dev/null 2>"$QEMU_ERR" &
QEMU_PID=$!

printf '  booting (pid %s), waiting up to %ss for a login prompt\n' "$QEMU_PID" "$TIMEOUT"

# ---- wait for getty -----------------------------------------------------
start=$SECONDS
deadline=$((start + TIMEOUT))
next_beat=$((start + 30))
login_line=""
failure=""

while process_alive "$QEMU_PID"; do
    # Buildroot's getty prints "<hostname> login:" and a trailing CR is
    # whitespace in the C locale. -a keeps grep from treating a stray NUL in
    # the serial stream as "binary file".
    if login_line=$(grep -a -m1 -E 'login:[[:space:]]*$' "$LOG" 2>/dev/null); then
        break
    fi
    # Do not sit out the whole timeout on an obvious kernel failure.
    if grep -a -qE 'Kernel panic|No working init found|Attempted to kill init' "$LOG" 2>/dev/null; then
        failure="kernel failure in serial log"
        break
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
        failure="timed out after ${TIMEOUT}s without a login prompt"
        break
    fi
    if [ "$SECONDS" -ge "$next_beat" ]; then
        printf '  ... %ss still booting; tail: %s\n' \
            "$((SECONDS - start))" "$(tail -n 1 "$LOG" 2>/dev/null | tr -d '\r')"
        next_beat=$((SECONDS + 30))
    fi
    sleep 2
done

# A prompt printed in the instant between the last poll and QEMU exiting would
# otherwise be missed, so look once more before deciding.
if [ -z "$login_line" ]; then
    login_line=$(grep -a -m1 -E 'login:[[:space:]]*$' "$LOG" 2>/dev/null || true)
fi

elapsed=$((SECONDS - start))

if [ -n "$login_line" ]; then
    login_line=$(printf '%s' "$login_line" | tr -d '\r')
    stop_qemu
    echo
    echo "PASS: login prompt reached after ${elapsed}s"
    printf '  %s\n' "$login_line"
    echo "  log: $LOG"
    exit 0
fi

if [ -z "$failure" ]; then
    # QEMU is gone. Reap it and keep its exit status as evidence.
    QEMU_RC=0
    wait "$QEMU_PID" || QEMU_RC=$?
    QEMU_PID=""
    failure="QEMU exited (status ${QEMU_RC}) before printing a login prompt"
else
    stop_qemu
fi

echo
echo "FAIL: $failure (after ${elapsed}s)"
echo "  image dir: $IMG_DIR"
echo "  log      : $LOG"
if [ -s "$QEMU_ERR" ]; then
    echo "  qemu stderr: $QEMU_ERR"
    tail -n 20 "$QEMU_ERR" | sed 's/^/    /'
fi
echo "  ---- last 40 lines of serial log ----"
if [ -s "$LOG" ]; then
    tail -n 40 "$LOG"
else
    echo "  (serial log is empty; QEMU produced no console output)"
fi
echo "  -------------------------------------"
exit 1
