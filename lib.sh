# Shared names and helpers, sourced by the masterclass scripts.
# shellcheck shell=bash disable=SC2034

FLAG=--yes-this-is-a-throwaway-vps
BASE=/root/masterclass-nginx
STATE=$BASE/state

STUDENT=student
STUDENT_HOME=/home/$STUDENT
SSHD_DROPIN=/etc/ssh/sshd_config.d/00-masterclass.conf

DECOY_UNIT=report-batch.service
DECOY_BIN=/usr/local/bin/report-batch

RESERVE_UNIT=legacy-dashboard.service
RESERVE_DIR=/var/lib/legacy-dashboard

MNT=/srv/demo-data
IMG=/var/lib/demo-data/disk.img
IMG_SIZE=200M
PRISTINE_IMG=$STATE/demo-data.img
FSTAB_LINE="$IMG $MNT ext4 loop,nofail 0 0"
ARCHIVE=backups/2023/site-backup-2023-03-14.tar
LEGIT_FILES=(README.txt uploads/welcome.txt uploads/team.jpg exports/2026-09-report.csv)

NGINX_SNAPSHOT=$STATE/etc-nginx.tar
DEMO_CONF=/etc/nginx/conf.d/demo.conf
WEBROOT=/var/www/demo
TYPO_LINE='    root /var/www/demo'

die() {
    echo "error: $*" >&2
    exit 1
}

# Sets ARGS to the arguments without the safety flag.
parse_args() {
    local a ok=0
    ARGS=()
    for a in "$@"; do
        if [[ $a == "$FLAG" ]]; then ok=1; else ARGS+=("$a"); fi
    done
    ((ok)) || die "this script creates users, sudo rules and mounts. Run it on a throwaway VPS only, with $FLAG"
    ((EUID == 0)) || die "run as root"
}

write_demo_conf() {
    cat >"$DEMO_CONF" <<EOF
client_body_temp_path $MNT/tmp/body;

server {
    listen 80 default_server;
    server_name _;

$TYPO_LINE
    index index.html;

    access_log /var/log/nginx/demo.access.log;
    error_log /var/log/nginx/demo.error.log;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /uploads/ {
        alias $MNT/uploads/;
    }
}
EOF
}

write_webroot() {
    rm -rf "$WEBROOT"
    install -d -m 755 "$WEBROOT"
    cat >"$WEBROOT/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Demo</title></head>
<body><h1>Demo site is up</h1></body>
</html>
EOF
    chmod 644 "$WEBROOT/index.html"
}

reserve_off() {
    systemctl disable --now "$RESERVE_UNIT" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/$RESERVE_UNIT"
    rm -rf "$RESERVE_DIR"
    systemctl daemon-reload
}
