#!/bin/bash
# Put the machine back in the exact starting state, from any state.
# Usage: ./reset.sh --yes-this-is-a-throwaway-vps [--no-check]
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
parse_args "$@"

run_check=1
for a in "${ARGS[@]}"; do
    case $a in
    --no-check) run_check=0 ;;
    *) die "unknown option $a" ;;
    esac
done

[[ -f $PRISTINE_IMG && -f $NGINX_SNAPSHOT ]] || die "state missing, run setup.sh first"
[[ -f $STATE/student.pub || -f $STATE/student.hash ]] || die "no student key or password in state, run setup.sh first"
start=$SECONDS

ensure_student() {
    id "$STUDENT" >/dev/null 2>&1 || useradd -m -s /bin/bash "$STUDENT"
    if [[ -f $STATE/student.hash ]]; then
        usermod -p "$(<"$STATE/student.hash")" "$STUDENT"
    else
        # A "*" password keeps key login working where "!" would count as a locked account.
        usermod -p '*' "$STUDENT"
    fi
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$STUDENT" >/etc/sudoers.d/.student.new
    visudo -cqf /etc/sudoers.d/.student.new
    chmod 440 /etc/sudoers.d/.student.new
    mv /etc/sudoers.d/.student.new "/etc/sudoers.d/$STUDENT"
}

clean_student_home() {
    install -d -o "$STUDENT" -g "$STUDENT" "$STUDENT_HOME"
    find "$STUDENT_HOME" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    cp -a /etc/skel/. "$STUDENT_HOME/"
    install -d -m 700 "$STUDENT_HOME/.ssh"
    if [[ -f $STATE/student.pub ]]; then
        install -m 600 "$STATE/student.pub" "$STUDENT_HOME/.ssh/authorized_keys"
    fi
    chown -R "$STUDENT:$STUDENT" "$STUDENT_HOME"
    find /tmp /var/tmp -mindepth 1 -user "$STUDENT" -delete 2>/dev/null || true
}

# The 00- prefix matters: sshd keeps the first value it reads, and cloud images ship a 50- file that disables passwords.
ensure_sshd() {
    if [[ -f $STATE/student.hash ]]; then
        printf 'Match User %s\n    PasswordAuthentication yes\n' "$STUDENT" >"$SSHD_DROPIN"
    else
        rm -f "$SSHD_DROPIN"
    fi
    sshd -t
    systemctl reload ssh
}

ensure_decoy() {
    cat >"$DECOY_BIN" <<'EOF'
#!/bin/bash
for _ in $(seq "$(nproc)"); do
    while :; do :; done &
done
wait
EOF
    chmod 755 "$DECOY_BIN"
    cat >"/etc/systemd/system/$DECOY_UNIT" <<EOF
[Unit]
Description=Nightly report batch
After=network.target

[Service]
ExecStart=$DECOY_BIN
Nice=19
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl unmask "$DECOY_UNIT" >/dev/null 2>&1 || true
    systemctl daemon-reload
    systemctl enable -q "$DECOY_UNIT"
    systemctl restart "$DECOY_UNIT"
}

restore_data() {
    local dev
    if mountpoint -q "$MNT"; then
        umount "$MNT" 2>/dev/null || {
            fuser -km "$MNT" >/dev/null 2>&1 || true
            sleep 1
            umount "$MNT"
        }
    fi
    while read -r dev; do
        umount "$dev" 2>/dev/null || true
        losetup -d "$dev" 2>/dev/null || true
    done < <(losetup -l -n -O NAME -j "$IMG" 2>/dev/null)

    install -d -m 755 "$(dirname "$IMG")" "$MNT"
    cp "$PRISTINE_IMG" "$IMG"
    if ! grep -qxF "$FSTAB_LINE" /etc/fstab; then
        sed -i "\\|[[:space:]]${MNT}[[:space:]]|d" /etc/fstab
        echo "$FSTAB_LINE" >>/etc/fstab
    fi
    systemctl daemon-reload
    mount "$MNT"
}

restore_nginx() {
    rm -rf /etc/nginx
    tar -C /etc -xf "$NGINX_SNAPSHOT"
    write_demo_conf
    write_webroot
    find /var/log/nginx -mindepth 1 \( -name '*.gz' -o -name '*.log.*' \) -delete
    find /var/log/nginx -mindepth 1 -name '*.log' -exec truncate -s 0 {} +
}

pkill -KILL -u "$STUDENT" 2>/dev/null || true
reserve_off
systemctl stop nginx 2>/dev/null || true
ensure_student
clean_student_home
ensure_sshd
ensure_decoy
restore_data
restore_nginx

journalctl -q --rotate
journalctl -q --vacuum-time=1s
systemctl reset-failed nginx 2>/dev/null || true
systemctl restart nginx 2>/dev/null || true

echo "reset done in $((SECONDS - start))s"
if ((run_check)); then
    exec "$BASE/check.sh" "$FLAG"
fi
