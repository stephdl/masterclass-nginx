#!/bin/bash
# Verify the starting state before the student connects. Exit 1 if anything fails.
# Usage: ./check.sh --yes-this-is-a-throwaway-vps [--wait-load]
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
parse_args "$@"

wait_load=0
for a in "${ARGS[@]}"; do
    case $a in
    --wait-load) wait_load=1 ;;
    *) die "unknown option $a" ;;
    esac
done

fails=0
check() {
    local desc=$1
    shift
    if "$@" >/dev/null 2>&1; then
        echo "PASS  $desc"
    else
        echo "FAIL  $desc"
        fails=$((fails + 1))
    fi
}

ncpu=$(nproc)

load_high() {
    awk -v n="$ncpu" '{ exit !($1 >= 0.6 * n) }' /proc/loadavg
}

decoy_workers() {
    local main
    main=$(systemctl show -p MainPID --value "$DECOY_UNIT")
    [[ $main != 0 ]] || return 1
    [[ $(pgrep -c -P "$main") -eq $ncpu ]] || return 1
    [[ $(ps -o ni= --ppid "$main" | sort -u | tr -d ' ') == 19 ]]
}

nginx_t_typo() {
    local out
    out=$(nginx -t 2>&1)
    grep -qF "invalid number of arguments in \"root\" directive in $DEMO_CONF:" <<<"$out" &&
        ! grep -q 'No space left' <<<"$out"
}

journal_typo() {
    journalctl -u nginx --no-pager -q | grep -qF 'invalid number of arguments in "root" directive'
}

status_typo() {
    local out
    out=$(systemctl status nginx --no-pager -l 2>&1)
    grep -qF 'invalid number of arguments in "root" directive' <<<"$out"
}

disk_full() {
    [[ $(findmnt -n -o FSTYPE "$MNT") == ext4 ]] &&
        [[ $(findmnt -n -o SOURCE "$MNT") == /dev/loop* ]] &&
        [[ $(df --output=avail -B1 "$MNT" | tail -1) -eq 0 ]] &&
        [[ $(df --output=pcent "$MNT" | tail -1 | tr -d ' ') == 100% ]]
}

archive_ok() {
    local f=$MNT/$ARCHIVE
    [[ -f $f ]] && (($(stat -c %s "$f") > 150 * 1024 * 1024)) &&
        [[ $(date -d "@$(stat -c %Y "$f")" +%Y) == 2023 ]]
}

legit_ok() {
    local f
    for f in "${LEGIT_FILES[@]}"; do [[ -s $MNT/$f ]] || return 1; done
    [[ -d $MNT/tmp && ! -e $MNT/tmp/body ]]
}

# Fix the typo in a throwaway copy: the only remaining error must be ENOSPC.
enospc_armed() {
    local t out
    t=$(mktemp -d "$STATE/check.XXXXXX")
    sed "s|^$TYPO_LINE\$|$TYPO_LINE;|" "$DEMO_CONF" >"$t/demo.conf"
    printf 'events {}\nhttp { include %s/demo.conf; }\n' "$t" >"$t/nginx.conf"
    out=$(nginx -t -c "$t/nginx.conf" 2>&1)
    rm -rf "$t"
    grep -qF "mkdir() \"$MNT/tmp/body\" failed (28: No space left on device)" <<<"$out"
}

no_leftovers() {
    [[ ! -e /etc/nginx/sites-enabled/default ]] &&
        [[ -z $(find /etc/nginx \( -name '*.orig' -o -name '*~' -o -name '*.bak' -o -name '*.save' -o -name '*.sw?' \) -print -quit) ]] &&
        ! grep -q '#' "$DEMO_CONF"
}

sudo_with_password() {
    [[ $(sudo -l -U "$STUDENT") == *"(ALL) ALL"* ]] && [[ $(sudo -l -U "$STUDENT") != *NOPASSWD* ]]
}

password_auth_ok() {
    local stu root
    stu=$(sshd -T -C "user=$STUDENT,host=test,addr=192.0.2.1")
    root=$(sshd -T -C "user=root,host=test,addr=192.0.2.1")
    grep -qx 'passwordauthentication yes' <<<"$stu" && grep -qx 'passwordauthentication no' <<<"$root"
}

student_home_clean() {
    [[ ! -s $STUDENT_HOME/.bash_history ]] && [[ ! -e $STUDENT_HOME/.lesshst ]] && [[ ! -e $STUDENT_HOME/.local ]]
}

if ((wait_load)); then
    echo "waiting for the load average to rise (up to 2 minutes)"
    for _ in $(seq 24); do load_high && break; sleep 5; done
fi

check "user $STUDENT exists" id "$STUDENT"
if [[ -f $STATE/student.hash ]]; then
    check "$STUDENT has sudo with password" sudo_with_password
else
    check "$STUDENT has passwordless sudo" runuser -u "$STUDENT" -- sudo -n true
fi
if [[ -f $STATE/student.pub ]]; then
    check "$STUDENT authorized_keys is a valid key" ssh-keygen -lf "$STUDENT_HOME/.ssh/authorized_keys"
fi
if [[ -f $STATE/student.hash ]]; then
    check "$STUDENT password is the one from setup" test "$(getent shadow "$STUDENT" | cut -d: -f2)" = "$(<"$STATE/student.hash")"
    check "sshd accepts passwords for $STUDENT only" password_auth_ok
fi
check "$STUDENT home has no history or traces" student_home_clean
check "$BASE is mode 700" test "$(stat -c %a "$BASE")" = 700
check "$BASE unreadable by $STUDENT without sudo" bash -c "! runuser -u $STUDENT -- ls $BASE"

check "$DECOY_UNIT active and enabled" bash -c "systemctl is-active -q $DECOY_UNIT && systemctl is-enabled -q $DECOY_UNIT"
check "$DECOY_UNIT runs $ncpu workers at nice 19" decoy_workers
check "load average >= 0.6 x $ncpu vCPU (rises within ~1 min)" load_high

check "nginx is failed" test "$(systemctl is-failed nginx)" = failed
check "systemctl status shows the root directive error" status_typo
check "journal shows the root directive error" journal_typo
check "nginx -t shows the typo with file and line, no ENOSPC yet" nginx_t_typo
check "default site removed, no backup files, no comments in demo.conf" no_leftovers

check "fstab has exactly one $MNT line" test "$(grep -c "[[:space:]]${MNT}[[:space:]]" /etc/fstab)" = 1
check "$MNT is a loop ext4 mount, 100% used, 0 available" disk_full
check "forgotten archive present (>150 MB, from 2023)" archive_ok
check "legitimate files present, tmp/body absent" legit_ok
check "after the typo fix, nginx -t fails with ENOSPC" enospc_armed

if [[ -f $PORT80_MARK ]]; then
    check "$RESERVE_UNIT active and enabled" bash -c "systemctl is-active -q $RESERVE_UNIT && systemctl is-enabled -q $RESERVE_UNIT"
    check "port 80 answers with the legacy dashboard" bash -c "curl -s http://localhost | grep -qF 'Legacy dashboard'"
else
    check "nothing listens on port 80" bash -c "[[ -z \$(ss -Hltn 'sport = :80') ]]"
    check "$RESERVE_UNIT is off" bash -c "! systemctl is-active -q $RESERVE_UNIT"
fi

if ((fails)); then
    echo "$fails check(s) failed"
    exit 1
fi
echo "all checks passed"
