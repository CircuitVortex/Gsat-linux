#!/bin/sh
# Post-build hook: banner, SSH policy, serial convenience.
# Buildroot passes BR2_* symbols in the environment.
set -eu

TARGET_DIR="$1"
: "${TARGET_DIR:?target dir not set}"

# --- login banner -------------------------------------------------------
if [ "${BR2_PACKAGE_GSAT_BANNER:-y}" = "y" ]; then
    cat > "${TARGET_DIR}/etc/motd" <<'EOF'

  GSAT MB86H615 - headless ARM1176 build
  ---------------------------------------
  console : serial ttyAMA0 @ 115200
  ssh     : port 22 (host 2222 when run under QEMU)
  user    : gsat-mb86h615   (passwd to change)
  root    : su -  (ssh login as root is disabled)

EOF

    mkdir -p "${TARGET_DIR}/etc/profile.d"
    cat > "${TARGET_DIR}/etc/profile.d/00-gsat.sh" <<'EOF'
# Quiet, useful prompt for the headless console.
PS1='\u@\h:\w\$ '
export PS1
command -v ip >/dev/null 2>&1 && {
    printf 'ip      : %s\n' "$(ip -4 -o addr show 2>/dev/null | awk '{print $2" "$4}' | paste -sd' ' -)"
}
printf 'kernel  : %s\n' "$(uname -sr)"
EOF
    chmod 0755 "${TARGET_DIR}/etc/profile.d/00-gsat.sh"
fi

# --- SSH: generate host keys at boot, no root login over ssh ------------
mkdir -p "${TARGET_DIR}/etc/dropbear"
mkdir -p "${TARGET_DIR}/etc/default"
cat > "${TARGET_DIR}/etc/default/dropbear" <<'EOF'
# -R: generate host keys if missing
# -w: refuse root logins over ssh
DROPBEAR_ARGS="-R -w"
EOF

# --- keep the image lean ------------------------------------------------
mkdir -p "${TARGET_DIR}/root"
chmod 0700 "${TARGET_DIR}/root"

echo "post-build: banner + ssh policy applied"
