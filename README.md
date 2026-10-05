# masterclass-nginx

Scripts for a one-to-one Linux troubleshooting session. A beginner connects to a throwaway VPS and repairs a broken nginx.

Run everything as root on a throwaway VPS only. The scripts create a user with sudo (asks the password in password mode, passwordless in key mode), a loop mount, systemd units, and can open SSH passwords for that user.

## The failures

1. Decoy: `report-batch.service` burns one CPU per vCPU at nice 19. Unrelated to nginx.
2. Typo: missing `;` after `root /var/www/demo` in `/etc/nginx/conf.d/demo.conf` line 7. nginx reports line 8.
3. Full disk: `/srv/demo-data` is 100% full because of `backups/2023/site-backup-2023-03-14.tar`. The error only shows after the typo is fixed.
4. Optional: `extra-port80.sh on` holds port 80 with `legacy-dashboard.service`.

Solutions and real outputs are in `TRAINER.md` (French).

## Provision

Create a fresh Debian 13 VPS, just before the session.

Copy the files:

```
ssh root@VPS mkdir -m 700 /tmp/mcs
scp *.sh TRAINER.md README.md root@VPS:/tmp/mcs/
```

Run the setup with a password (or `STUDENT_PUBKEY="ssh-ed25519 ..."` for a key):

```
ssh root@VPS 'STUDENT_PASSWORD="..." /tmp/mcs/setup.sh --yes-this-is-a-throwaway-vps'
```

It ends with `all checks passed`. On a fresh 2 vCPU VPS it takes about one minute. It needs 600 MB free on `/var`.

Remove the copy:

```
ssh root@VPS rm -rf /tmp/mcs
```

Give the student `ssh student@VPS` and the password. Destroy the VPS after the session.

Between two sessions:

```
ssh root@VPS /root/masterclass-nginx/reset.sh --yes-this-is-a-throwaway-vps
```

Reset takes about 4 seconds. It kills the student sessions, so never run it during a session.

## Tests

Last full run on a fresh Debian 13 VPS (nginx 1.26.3, 2 vCPU), password mode:

- `bash -n` and `shellcheck -x` clean.
- Provisioning as above: 60 s until `all checks passed`.
- Second setup: 5 s, one fstab line, loop device, mount, user, sudoers file and SSH drop-in.
- Student walkthrough over password SSH, sudo asking the password, from the load to `curl -I` returning 200.
- ENOSPC appears only after the typo fix.
- Port 80 reserve: on, student fix (including `kill` coming back), off.
- Reset from the fixed state: 5 s.
- Reset from a damaged state: 5 s. Damage was: files deleted on the disk, `.orig` file, broken nginx.conf, decoy disabled, sudoers and SSH drop-in removed, password changed, history and files left, a process inside the mount, mount read-only, reserve on.
- Reboot: student SSH back after 29 s, all checks pass.

Not tested: Debian 12, Ubuntu 22.04 and 24.04.

## Debug

Run the check first. Every FAIL line names what is wrong:

```
/root/masterclass-nginx/check.sh --yes-this-is-a-throwaway-vps
```

Then:

1. Load FAIL right after setup or reset: wait one minute and run the check again.
2. Any other FAIL: run `reset.sh`. It rebuilds the starting state from any state.
3. Reset fails with "state missing": run `setup.sh` again.
4. Disk FAIL ("not full", or mkdir works): rebuild the image with `setup.sh --yes-this-is-a-throwaway-vps --rebuild-image`.
5. Student cannot log in: `sshd -T -C user=student,host=x,addr=192.0.2.1 | grep passwordauth` must say `yes`. Then check `journalctl -u ssh -e`.
6. Still stuck: run the failing script with `bash -x` to see each step.
