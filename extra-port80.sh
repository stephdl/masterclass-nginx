#!/bin/bash
# Reserve scenario: something else holds port 80, so nginx cannot start.
# Usage: ./extra-port80.sh --yes-this-is-a-throwaway-vps on|off
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
parse_args "$@"

on() {
    nginx -t -q 2>/dev/null || die "nginx -t fails, finish the main scenario first"
    install -d -m 755 "$RESERVE_DIR"
    echo '<h1>Legacy dashboard</h1>' >"$RESERVE_DIR/index.html"
    cat >"/etc/systemd/system/$RESERVE_UNIT" <<EOF
[Unit]
Description=Legacy dashboard
After=network.target

[Service]
ExecStart=/usr/bin/python3 -m http.server 80 --bind 0.0.0.0 --directory $RESERVE_DIR
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl stop nginx
    systemctl enable -q --now "$RESERVE_UNIT"
    for _ in $(seq 20); do
        [[ -n $(ss -Hltn 'sport = :80') ]] && break
        sleep 0.25
    done
    if systemctl restart nginx 2>/dev/null; then
        die "nginx started anyway, check $RESERVE_UNIT"
    fi
    echo "reserve on: nginx failed, port 80 is held by $RESERVE_UNIT"
}

off() {
    reserve_off
    systemctl reset-failed nginx 2>/dev/null || true
    systemctl restart nginx || true
    echo "reserve off: nginx is $(systemctl is-active nginx)"
}

case ${ARGS[0]:-} in
on) on ;;
off) off ;;
*) die "usage: $0 $FLAG on|off" ;;
esac
