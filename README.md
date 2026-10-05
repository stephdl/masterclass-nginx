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

It ends with `all checks passed`. It takes about one minute.

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

Done on Debian 13, nginx 1.26.3, 2 vCPU:

- `bash -n` and `shellcheck -x` clean.
- Setup refuses without the flag, without a key or password, and with an invalid key.
- Setup run three times: one fstab line, one loop device, one sudoers file.
- Full student walkthrough over SSH, from the load to `curl -I` returning 200.
- ENOSPC appears only after the typo fix.
- Port 80 reserve on and off.
- Reset from the fixed state and from a damaged one (sudoers removed, nginx.conf broken, `.orig` file, decoy disabled, shell inside the mount, mount read-only, password changed).
- Reboot: the mount, the decoy and the failed nginx come back.
- Password login works for `student`, root stays key only.

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
