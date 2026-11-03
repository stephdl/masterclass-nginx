#!/bin/bash
# Build the nginx troubleshooting scenario on a fresh VPS.
# Usage: STUDENT_PASSWORD='...' ./setup.sh --yes-this-is-a-throwaway-vps
#        STUDENT_PUBKEY="ssh-ed25519 AAAA..." ./setup.sh --yes-this-is-a-throwaway-vps
#        ./setup.sh --yes-this-is-a-throwaway-vps [--rebuild-image] [--port80] [/path/to/student.pub]
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
parse_args "$@"

rebuild=0
reset_opts=()
key_src=${STUDENT_PUBKEY:-}
for a in "${ARGS[@]}"; do
    case $a in
    --rebuild-image) rebuild=1 ;;
    --port80) reset_opts+=(--port80) ;;
    -*) die "unknown option $a" ;;
    *) key_src=$a ;;
    esac
done

password=${STUDENT_PASSWORD:-}
[[ -n $key_src || -n $password ]] || die "no way for the student to log in. Set STUDENT_PASSWORD, STUDENT_PUBKEY, or pass a public key file"
keyfile=$(mktemp)
trap 'rm -f "$keyfile"' EXIT
if [[ -n $key_src ]]; then
    if [[ -f $key_src ]]; then key=$(<"$key_src"); else key=$key_src; fi
    [[ $key != *PRIVATE\ KEY* ]] || die "this is a private key, give the public one"
    printf '%s\n' "$key" >"$keyfile"
    ssh-keygen -lf "$keyfile" >/dev/null 2>&1 || die "not a valid SSH public key: $key_src"
fi

install_self() {
    [[ $here == "$BASE" ]] && return
    install -d -m 700 "$BASE"
    install -m 700 "$here"/{lib,setup,reset,check,extra-port80}.sh "$BASE/"
    install -m 600 "$here/TRAINER.md" "$BASE/"
}

install_packages() {
    local missing=() p
    for p in nginx htop curl sudo psmisc; do
        dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || missing+=("$p")
    done
    ((${#missing[@]})) || return 0
    apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${missing[@]}"
}

# Taken once, before demo.conf exists, so reset can repair any damage to /etc/nginx.
snapshot_nginx() {
    [[ -f $NGINX_SNAPSHOT ]] && return
    rm -f /etc/nginx/sites-enabled/default "$DEMO_CONF"
    tar -C /etc -cf "$NGINX_SNAPSHOT" nginx
}

build_image() {
    local work mnt avail chunk i
    work=$(mktemp -d /var/tmp/demo-data.XXXXXX)
    mnt=$work/mnt
    # shellcheck disable=SC2064
    trap "umount '$mnt' 2>/dev/null; rm -rf '$work' '$keyfile'" EXIT

    truncate -s "$IMG_SIZE" "$work/disk.img"
    mkfs.ext4 -q -F -m 0 -L demo-data -E lazy_itable_init=0,lazy_journal_init=0 "$work/disk.img"
    mkdir "$mnt"
    # With delayed allocation ext4 keeps a few blocks in reserve and the disk never reaches 0 available.
    mount -o loop,nodelalloc "$work/disk.img" "$mnt"

    install -d -m 755 "$mnt"/{uploads,exports,tmp,backups/2023}
    cat >"$mnt/README.txt" <<'EOF'
Demo data volume.
uploads/  files served by the web site under /uploads/
exports/  monthly reports, keep 12 months
EOF
    echo "Welcome to the demo site." >"$mnt/uploads/welcome.txt"
    head -c 48K /dev/urandom >"$mnt/uploads/team.jpg"
    printf 'date,visits,orders\n2026-09-01,412,17\n2026-09-02,388,12\n2026-09-03,450,21\n' \
        >"$mnt/exports/2026-09-report.csv"
    chmod 644 "$mnt/README.txt" "$mnt/uploads"/* "$mnt/exports"/*
    touch -d '-12 days' "$mnt/README.txt" "$mnt/uploads"/* "$mnt/exports"/*

    # Leave a few MB for tar headers, then pad with zeros: tar ignores trailing zero blocks.
    avail=$(df --output=avail -B1M "$mnt" | tail -1)
    chunk=$(((avail - 4) / 12))
    install -d "$work/site/var/www/html/media" "$work/site/db"
    for i in $(seq 1 11); do
        head -c "${chunk}M" /dev/urandom >"$work/site/var/www/html/media/video-$((2022 * 100 + i)).mp4"
    done
    head -c "${chunk}M" /dev/urandom >"$work/site/db/site.sql.gz"
    tar --mtime='2023-03-14 02:10' --owner=0 --group=0 -C "$work/site" -cf "$mnt/$ARCHIVE" .
    rm -rf "$work/site"
    cat /dev/zero >>"$mnt/$ARCHIVE" 2>/dev/null || true
    # The archive can leave a block or two it cannot grow into, a small new file takes them.
    {
        echo "2023-03-14 02:10:01 backup started"
        echo "2023-03-14 02:14:37 archive written: $(basename "$ARCHIVE")"
        yes "2023-03-14 02:14:38 upload to offsite storage failed: connection timed out, retrying"
    } >"$mnt/${ARCHIVE%.tar}.log" 2>/dev/null || true
    sync
    # A last free block can stay usable for metadata only: empty directories take it.
    for d in uploads/thumbnails uploads/avatars exports/drafts; do
        [[ $(df --output=avail -B1 "$mnt" | tail -1) -eq 0 ]] && break
        mkdir "$mnt/$d" 2>/dev/null || break
        sync
    done
    touch -d '2023-03-14 02:14' "$mnt/$ARCHIVE" "$mnt/${ARCHIVE%.tar}.log" "$mnt/backups/2023" "$mnt/backups"

    [[ $(df --output=avail -B1 "$mnt" | tail -1) -eq 0 ]] || die "image is not full"
    if mkdir "$mnt/tmp/probe" 2>/dev/null; then die "mkdir still works on the full image"; fi

    umount "$mnt"
    mv "$work/disk.img" "$PRISTINE_IMG"
    rm -rf "$work"
    trap 'rm -f "$keyfile"' EXIT
}

if ((rebuild)) || [[ ! -f $PRISTINE_IMG ]]; then
    # Pristine image, live copy and the temporary archive content during the build.
    free_mb=$(df --output=avail -BM /var | tail -1 | tr -dc 0-9)
    ((free_mb >= 600)) || die "need 600 MB free on /var, only ${free_mb} MB available"
fi
install_self
install_packages
install -d -m 700 "$STATE"
rm -f "$STATE/student.pub" "$STATE/student.hash"
[[ -s $keyfile ]] && install -m 600 "$keyfile" "$STATE/student.pub"
# Only the hash is kept, so reset can restore the password without storing it in clear.
if [[ -n $password ]]; then
    id "$STUDENT" >/dev/null 2>&1 || useradd -m -s /bin/bash "$STUDENT"
    printf '%s:%s\n' "$STUDENT" "$password" | chpasswd
    getent shadow "$STUDENT" | cut -d: -f2 >"$STATE/student.hash"
    chmod 600 "$STATE/student.hash"
fi
snapshot_nginx
if ((rebuild)) || [[ ! -f $PRISTINE_IMG ]]; then
    echo "building the data image, this takes a minute"
    build_image
fi

"$BASE/reset.sh" "$FLAG" "${reset_opts[@]}" --no-check
"$BASE/check.sh" "$FLAG" --wait-load
