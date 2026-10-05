# Masterclass nginx: trainer notes

These notes stay in `/root/masterclass-nginx` (mode 700). The student must not see them.

The goal is the method, not the commands: observe, read the journal, find the cause, fix, verify. Have the student repeat it for each failure.

All outputs below come from a real run on a fresh DigitalOcean droplet, official Debian 13 image (nginx 1.26.3, 2 vCPU, 2 GB). PIDs, dates and host names will differ on your machine.

## Preparation

Create a fresh Debian 13 VPS just before the session. From your workstation:

```
ssh root@VPS mkdir -m 700 /tmp/mcs
scp *.sh TRAINER.md README.md root@VPS:/tmp/mcs/
ssh root@VPS 'STUDENT_PASSWORD="the-password" /tmp/mcs/setup.sh --yes-this-is-a-throwaway-vps'
ssh root@VPS rm -rf /tmp/mcs
```

With a key instead of a password: `STUDENT_PUBKEY="ssh-ed25519 AAAA..."`, or the path to a `.pub` file as argument.

Times measured on a fresh machine:

| Step | Duration |
|---|---|
| Copy the files | 6 s |
| Setup (apt, disk image, reset, wait for the load) | 52 s |
| Total until `all checks passed` | 60 s |
| Second setup (nothing to redo) | 5 s |
| Reset between two sessions | 4 to 5 s |
| Reboot until the student can log in | 29 s |

Setup refuses to run without `--yes-this-is-a-throwaway-vps`, without a password or key, and with less than 600 MB free on `/var`.

In password mode, setup adds `/etc/ssh/sshd_config.d/00-masterclass.conf`, which allows passwords for `student` only. Root stays key only. sudo asks for the password, then remembers it for 15 minutes. The script keeps only the hash. Never write the password in a file.

Before each session:

```
/root/masterclass-nginx/reset.sh --yes-this-is-a-throwaway-vps
```

Reset kills the student sessions, restores the disk, the nginx config, the password, the SSH config and the home directory, and wipes the whole system journal. It ends with `check.sh`. If only the load check fails (the decoy was stopped), run `check.sh` again one minute later.

## Timeline (60 min)

| Time | Step |
|---|---|
| 0-5 | SSH login, where am I (`hostname`, `whoami`), reminder of the method |
| 5-15 | Decoy: the machine is busy |
| 15-35 | Failure 1: typo in the config |
| 35-55 | Failure 2: full disk |
| 55-60 | Debrief: walk through the reasoning again out loud |

If the student is fast, continue with the port 80 reserve.

Opening brief: "The web site on this machine does not answer any more. Find out why and fix it."

## Step 1: the decoy (CPU load)

```
$ uptime
 13:23:10 up 4 min,  1 user,  load average: 1.65, 0.67, 0.26

$ top
%Cpu(s):  0.0 us,  4.3 sy, 95.7 ni,  0.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st
    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
   3559 root      39  19    4488   1608   1328 R  90.9   0.1   0:14.91 report-batch
   3560 root      39  19    4488   1608   1328 R  90.9   0.1   0:14.98 report-batch

$ systemctl status report-batch
● report-batch.service - Nightly report batch
     Loaded: loaded (/etc/systemd/system/report-batch.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-10-05 13:22:54 UTC; 16s ago
     CGroup: /system.slice/report-batch.service
             ├─3554 /bin/bash /usr/local/bin/report-batch
             ├─3559 /bin/bash /usr/local/bin/report-batch
             └─3560 /bin/bash /usr/local/bin/report-batch
```

What to conclude: the load is real but unrelated to nginx. The CPU time is in `ni` (nice) and the processes have NI 19, so the machine stays responsive. Nothing gets killed. Note the observation and move on to nginx.

Trap: the student wants to kill `report-batch`. If they stop it, ask whether the site works again. It does not. Fixing what you see is not fixing the failure.

Hints:
1. Vague: "The machine is busy. Does that explain why the site does not answer?"
2. Precise: "Look at the NI column. What does 19 mean? Which service started these processes?"
3. Explicit: "It is an unrelated batch job. Look at `systemctl status nginx`."

## Step 2: the typo

Without sudo, the student sees that nginx is down, but not why:

```
$ systemctl status nginx
× nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled; preset: enabled)
     Active: failed (Result: exit-code) since Mon 2026-10-05 13:22:56 UTC; 14s ago
    Process: 3623 ExecStartPre=/usr/sbin/nginx -t -q -g daemon on; master_process on; (code=exited, status=1/FAILURE)

Warning: some journal files were not opened due to insufficient permissions.

$ journalctl -u nginx -e
Hint: You are currently not seeing messages from other users and the system.
      Users in groups 'adm', 'systemd-journal' can see all messages.
      Pass -q to turn off this notice.
-- No entries --
```

Trap: "No entries" does not mean "no error". It is a permission problem. Good moment to talk about sudo. The first sudo asks for the password:

```
$ sudo journalctl -u nginx -e
[sudo] password for student:
Oct 05 13:22:56 debian-s-2vcpu-2gb-fra1 systemd[1]: Starting nginx.service - A high performance web server and a reverse proxy server...
Oct 05 13:22:56 debian-s-2vcpu-2gb-fra1 nginx[3623]: 2026/10/05 13:22:56 [emerg] 3623#3623: invalid number of arguments in "root" directive in /etc/nginx/conf.d/demo.conf:8
Oct 05 13:22:56 debian-s-2vcpu-2gb-fra1 nginx[3623]: nginx: configuration file /etc/nginx/nginx.conf test failed
Oct 05 13:22:56 debian-s-2vcpu-2gb-fra1 systemd[1]: nginx.service: Control process exited, code=exited, status=1/FAILURE
Oct 05 13:22:56 debian-s-2vcpu-2gb-fra1 systemd[1]: nginx.service: Failed with result 'exit-code'.
Oct 05 13:22:56 debian-s-2vcpu-2gb-fra1 systemd[1]: Failed to start nginx.service - A high performance web server and a reverse proxy server.

$ sudo nginx -t
2026/10/05 13:23:23 [emerg] 3846#3846: invalid number of arguments in "root" directive in /etc/nginx/conf.d/demo.conf:8
nginx: configuration file /etc/nginx/nginx.conf test failed

$ cat -n /etc/nginx/conf.d/demo.conf
     6
     7	    root /var/www/demo
     8	    index index.html;
```

Trap: nginx reports line 8, but the mistake is on line 7. The semicolon is missing at the end of `root`, so nginx reads `root /var/www/demo index index.html;` as one directive with three arguments.

Solution:

```
sudo nano /etc/nginx/conf.d/demo.conf     # add ; at the end of line 7
sudo nginx -t
```

Hints:
1. Vague: "What does the journal say exactly? Read the whole message, not just "failed"."
2. Precise: "The message gives a file and a line. Open it. Look at the line just above too."
3. Explicit: "A semicolon is missing at the end of the `root` line."

Insist: test with `nginx -t` before restarting.

## Step 3: the full disk (hidden failure)

Right after the fix, a new error shows up:

```
$ sudo nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
2026/10/05 13:23:36 [emerg] 3909#3909: mkdir() "/srv/demo-data/tmp/body" failed (28: No space left on device)
nginx: configuration file /etc/nginx/nginx.conf test failed

$ sudo systemctl restart nginx
Job for nginx.service failed because the control process exited with error code.
See "systemctl status nginx.service" and "journalctl -xeu nginx.service" for details.

$ sudo journalctl -u nginx -e
Oct 05 13:23:36 debian-s-2vcpu-2gb-fra1 nginx[3913]: 2026/10/05 13:23:36 [emerg] 3913#3913: mkdir() "/srv/demo-data/tmp/body" failed (28: No space left on device)
Oct 05 13:23:36 debian-s-2vcpu-2gb-fra1 nginx[3913]: nginx: configuration file /etc/nginx/nginx.conf test failed
```

Trap: "syntax is ok". The first failure is fixed, this is a second one. It was invisible before, because nginx stops at the first syntax error.

Investigation (excerpt of `df -h`, the real output also lists about ten `tmpfs` lines):

```
$ df -h
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda1        59G  1.5G   56G   3% /
/dev/vda15      124M  8.9M  115M   8% /boot/efi
/dev/loop0      182M  178M     0 100% /srv/demo-data

$ sudo du -sh /srv/demo-data/*
1.0K	/srv/demo-data/README.txt
178M	/srv/demo-data/backups
2.0K	/srv/demo-data/exports
12K	/srv/demo-data/lost+found
1.0K	/srv/demo-data/tmp
51K	/srv/demo-data/uploads

$ ls -la /srv/demo-data/backups/2023
-rw-r--r-- 1 root root        99 Mar 14  2023 site-backup-2023-03-14.log
-rw-r--r-- 1 root root 186449920 Mar 14  2023 site-backup-2023-03-14.tar
```

Trap: `/` is at 3%. A beginner often concludes "the disk is not full". Make them read every line of `df`, not only the first one. The path in the error message (`/srv/demo-data/...`) tells which disk to look at.

Before deleting, the student must check what the file is:

```
$ file /srv/demo-data/backups/2023/site-backup-2023-03-14.tar
/srv/demo-data/backups/2023/site-backup-2023-03-14.tar: POSIX tar archive (GNU)

$ tar tvf /srv/demo-data/backups/2023/site-backup-2023-03-14.tar | head
drwxr-xr-x root/root         0 2023-03-14 02:10 ./
drwxr-xr-x root/root         0 2023-03-14 02:10 ./var/www/html/media/
-rw-r--r-- root/root  14680064 2023-03-14 02:10 ./var/www/html/media/video-202207.mp4
...

$ cat /srv/demo-data/backups/2023/site-backup-2023-03-14.log
2023-03-14 02:10:01 backup started
2023-03-14 02:14:37 archive written: site-backup-2023-03-14.tar

$ cat /srv/demo-data/README.txt
Demo data volume.
uploads/  files served by the web site under /uploads/
exports/  monthly reports, keep 12 months
```

Trap: do not delete everything. `uploads/` is served by the site and `exports/` must be kept. Only the 2023 archive goes.

Solution:

```
$ sudo rm /srv/demo-data/backups/2023/site-backup-2023-03-14.tar
$ df -h /srv/demo-data
Filesystem      Size  Used Avail Use% Mounted on
/dev/loop0      182M  122K  178M   1% /srv/demo-data

$ sudo systemctl restart nginx
$ systemctl status nginx
● nginx.service - A high performance web server and a reverse proxy server
     Active: active (running) since Mon 2026-10-05 13:23:53 UTC; 25ms ago

$ curl -I http://localhost
HTTP/1.1 200 OK
Server: nginx
Content-Type: text/html
Content-Length: 102

$ curl http://localhost/uploads/welcome.txt
Welcome to the demo site.
```

Hints:
1. Vague: "What does "No space left on device" mean? On which disk?"
2. Precise: "`df -h` shows every disk. Then `du` to find what takes the space."
3. Explicit: "An old 2023 backup fills `/srv/demo-data`. Check it with `file`, delete it, restart."

End: ask for proof that it is fixed. "It restarted" is not enough. `curl -I` answering 200 is. The `curl` on `/uploads/` also proves the legitimate files are intact.

## Reserve: port 80 taken

Only once the main scenario is fixed (otherwise the script refuses with `nginx -t fails, finish the main scenario first`). As root:

```
$ /root/masterclass-nginx/extra-port80.sh --yes-this-is-a-throwaway-vps on
reserve on: nginx failed, port 80 is held by legacy-dashboard.service
```

What the student sees:

```
$ sudo journalctl -u nginx -e
Oct 05 13:24:09 debian-s-2vcpu-2gb-fra1 nginx[4159]: nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)
Oct 05 13:24:09 debian-s-2vcpu-2gb-fra1 nginx[4159]: nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)
Oct 05 13:24:10 debian-s-2vcpu-2gb-fra1 nginx[4159]: nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)
Oct 05 13:24:10 debian-s-2vcpu-2gb-fra1 nginx[4159]: nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)
Oct 05 13:24:11 debian-s-2vcpu-2gb-fra1 nginx[4159]: nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)
Oct 05 13:24:11 debian-s-2vcpu-2gb-fra1 nginx[4159]: nginx: [emerg] still could not bind()
Oct 05 13:24:11 debian-s-2vcpu-2gb-fra1 systemd[1]: Failed to start nginx.service - A high performance web server and a reverse proxy server.

$ sudo nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Trap: `nginx -t` passes, the config is fine. The problem is elsewhere.

```
$ sudo ss -ltnp 'sport = :80'
State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
LISTEN 0      5            0.0.0.0:80        0.0.0.0:*    users:(("python3",pid=4152,fd=3))

$ systemctl status 4152
● legacy-dashboard.service - Legacy dashboard
     Loaded: loaded (/etc/systemd/system/legacy-dashboard.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-10-05 13:24:08 UTC; 5s ago
   Main PID: 4152 (python3)
```

Trap: `kill` is not enough. The service has `Restart=always` and comes back with another PID:

```
$ sudo kill 4152
$ sudo ss -ltnp 'sport = :80'
LISTEN 0      5            0.0.0.0:80        0.0.0.0:*    users:(("python3",pid=4230,fd=3))
```

Solution:

```
$ sudo systemctl disable --now legacy-dashboard
Removed '/etc/systemd/system/multi-user.target.wants/legacy-dashboard.service'.
$ sudo systemctl restart nginx
$ curl -I http://localhost
HTTP/1.1 200 OK
```

Hints:
1. Vague: "The config is fine according to `nginx -t`. What does the journal say?"
2. Precise: "Something else uses port 80. What? `ss -ltnp`."
3. Explicit: "It is the `legacy-dashboard` service. Stop and disable it with systemctl."

To remove the reserve: `extra-port80.sh --yes-this-is-a-throwaway-vps off` (or just `reset.sh`).

## Things to keep in mind

The student has full sudo, so they can read these notes if they look for them. The only boundary is the throwaway VPS.

`reset.sh` wipes the whole system journal, not only nginx's. This is on purpose: the previous session must not leave the solution in `journalctl`.

Reset kills every process of the `student` user. Never run it during a session.

In password mode, the `student` SSH login is open to bots that try passwords. Provision the VPS just before the session and destroy it right after. The scripts add no firewall.

Tested only on a DigitalOcean droplet with Debian 13. Other providers, Debian 12 and Ubuntu 22.04/24.04 are not tested. On DigitalOcean, the image ships `/etc/ssh/sshd_config.d/50-cloud-init.conf` with `PasswordAuthentication no`. That is why our file is named `00-masterclass.conf`. With another provider, check that `check.sh` shows PASS on the SSH line.

Technical detail: the disk image is filled with `nodelalloc`. Without this option ext4 keeps a few blocks in reserve and `df` never shows 0 available.
