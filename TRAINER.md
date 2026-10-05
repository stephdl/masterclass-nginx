# Masterclass nginx : notes du formateur

Ces notes restent dans `/root/masterclass-nginx` (mode 700). L'élève ne doit pas les voir.

L'objectif est la méthode, pas les commandes : observer, lire le journal, trouver la cause, corriger, vérifier. Faites-la répéter à chaque panne.

Toutes les sorties ci-dessous viennent d'un vrai test sur un droplet DigitalOcean neuf, image officielle Debian 13 (nginx 1.26.3, 2 vCPU, 2 Go). Les PID, dates et noms de machine changeront chez vous.

## Préparation

Créez un VPS Debian 13 neuf juste avant la séance. Depuis votre poste :

```
ssh root@VPS mkdir -m 700 /tmp/mcs
scp *.sh TRAINER.md README.md root@VPS:/tmp/mcs/
ssh root@VPS 'STUDENT_PASSWORD="mot-de-passe" /tmp/mcs/setup.sh --yes-this-is-a-throwaway-vps'
ssh root@VPS rm -rf /tmp/mcs
```

Avec une clé au lieu d'un mot de passe : `STUDENT_PUBKEY="ssh-ed25519 AAAA..."`, ou le chemin d'un `.pub` en argument.

Temps mesurés sur une machine neuve :

| Étape | Durée |
|---|---|
| Copie des fichiers | 6 s |
| Setup (apt, image disque, reset, attente de la charge) | 52 s |
| Total jusqu'à `all checks passed` | 60 s |
| Second setup (rien à refaire) | 5 s |
| Reset entre deux séances | 4 à 5 s |
| Reboot jusqu'à ce que l'élève puisse se connecter | 29 s |

Le setup refuse de tourner sans `--yes-this-is-a-throwaway-vps`, sans mot de passe ni clé, et s'il reste moins de 600 Mo libres sur `/var`.

En mode mot de passe, le setup ajoute `/etc/ssh/sshd_config.d/00-masterclass.conf`, qui autorise les mots de passe pour `student` seulement. Root reste en clé. sudo demande le mot de passe, puis le garde 15 minutes. Le script ne garde que le hash. N'écrivez jamais le mot de passe dans un fichier.

Avant chaque séance :

```
/root/masterclass-nginx/reset.sh --yes-this-is-a-throwaway-vps
```

Le reset tue les sessions de l'élève, restaure le disque, la config nginx, le mot de passe, la conf SSH et le home, et vide tout le journal système. Il finit par `check.sh`. Si seule la charge est en FAIL (le leurre était arrêté), relancez `check.sh` une minute plus tard.

## Déroulé (60 min)

| Temps | Étape |
|---|---|
| 0-5 | Connexion SSH, où suis-je (`hostname`, `whoami`), rappel de la méthode |
| 5-15 | Leurre : la machine est chargée |
| 15-35 | Panne 1 : faute de frappe dans la config |
| 35-55 | Panne 2 : disque plein |
| 55-60 | Débrief : refaire la chaîne de raisonnement à voix haute |

Si l'élève va vite, enchaînez avec la réserve port 80.

Consigne de départ : « Le site web de cette machine ne répond plus. Trouve pourquoi et répare-le. »

## Étape 1 : le leurre (charge CPU)

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

Ce qu'il faut conclure : la charge est réelle mais sans rapport avec nginx. Le CPU est pris en `ni` (nice), les processus ont NI à 19 : la machine reste réactive. On ne tue rien. On note l'observation et on passe à nginx.

Piège : l'élève veut tuer `report-batch`. S'il l'arrête, demandez-lui si le site remarche. Non. Corriger ce qu'on voit n'est pas corriger la panne.

Indices :
1. Vague : « La machine est occupée. Est-ce que ça explique que le site ne réponde pas ? »
2. Précis : « Regarde la colonne NI. Que veut dire 19 ? Quel service a lancé ces processus ? »
3. Explicite : « C'est un batch sans rapport. Regarde `systemctl status nginx`. »

## Étape 2 : la faute de frappe

Sans sudo, l'élève voit que nginx est en panne, mais pas pourquoi :

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

Piège : « No entries » ne veut pas dire « pas d'erreur ». C'est un problème de droits. Bon moment pour parler de sudo. Le premier sudo demande le mot de passe :

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

Piège : nginx annonce la ligne 8, mais la faute est ligne 7. Le point-virgule manque à la fin de `root`, donc nginx lit `root /var/www/demo index index.html;` comme une seule directive à trois arguments.

Solution :

```
sudo nano /etc/nginx/conf.d/demo.conf     # ajouter ; à la fin de la ligne 7
sudo nginx -t
```

Indices :
1. Vague : « Que dit le journal exactement ? Lis le message en entier, pas juste "failed". »
2. Précis : « Le message donne un fichier et une ligne. Ouvre-le. Regarde aussi la ligne juste au-dessus. »
3. Explicite : « Il manque un point-virgule à la fin de la ligne `root`. »

Insistez : on teste avec `nginx -t` avant de redémarrer.

## Étape 3 : le disque plein (panne cachée)

Juste après la correction, une nouvelle erreur apparaît :

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

Piège : « syntax is ok ». La première panne est bien réparée, c'est une deuxième panne. Elle était invisible avant, car nginx s'arrête à la première erreur de syntaxe.

Enquête (extrait de `df -h`, la vraie sortie liste aussi une dizaine de `tmpfs`) :

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

Piège : `/` est à 3 %. Un débutant conclut souvent « le disque n'est pas plein ». Faites lire toutes les lignes de `df`, pas seulement la première. Le chemin du message d'erreur (`/srv/demo-data/...`) dit sur quel disque regarder.

Avant de supprimer, l'élève doit vérifier ce qu'est le fichier :

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

Piège : ne pas tout effacer. `uploads/` est servi par le site, `exports/` est à garder. Seule l'archive de 2023 part.

Solution :

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

Indices :
1. Vague : « Que veut dire "No space left on device" ? Sur quel disque ? »
2. Précis : « `df -h` montre tous les disques. Puis `du` pour trouver ce qui prend la place. »
3. Explicite : « Une vieille sauvegarde de 2023 remplit `/srv/demo-data`. Vérifie avec `file`, supprime-la, redémarre. »

Fin : demandez la preuve que c'est réparé. « Il a redémarré » ne suffit pas. `curl -I` qui répond 200, oui. Le `curl` sur `/uploads/` prouve aussi que les fichiers légitimes sont intacts.

## Réserve : le port 80 occupé

Uniquement une fois le scénario principal réparé (le script refuse sinon, avec `nginx -t fails, finish the main scenario first`). En root :

```
$ /root/masterclass-nginx/extra-port80.sh --yes-this-is-a-throwaway-vps on
reserve on: nginx failed, port 80 is held by legacy-dashboard.service
```

Ce que l'élève voit :

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

Piège : `nginx -t` passe, la config est bonne. Le problème est ailleurs.

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

Piège : `kill` ne suffit pas. Le service a `Restart=always` et revient avec un autre PID :

```
$ sudo kill 4152
$ sudo ss -ltnp 'sport = :80'
LISTEN 0      5            0.0.0.0:80        0.0.0.0:*    users:(("python3",pid=4230,fd=3))
```

Solution :

```
$ sudo systemctl disable --now legacy-dashboard
Removed '/etc/systemd/system/multi-user.target.wants/legacy-dashboard.service'.
$ sudo systemctl restart nginx
$ curl -I http://localhost
HTTP/1.1 200 OK
```

Indices :
1. Vague : « La config est bonne d'après `nginx -t`. Que dit le journal ? »
2. Précis : « Quelqu'un d'autre utilise le port 80. Qui ? `ss -ltnp`. »
3. Explicite : « C'est le service `legacy-dashboard`. Arrête-le et désactive-le avec systemctl. »

Pour retirer la réserve : `extra-port80.sh --yes-this-is-a-throwaway-vps off` (ou simplement `reset.sh`).

## Points d'attention

L'élève a sudo complet. Il peut donc lire ces notes s'il le cherche. La seule frontière est le VPS jetable.

`reset.sh` vide tout le journal système, pas seulement celui de nginx. C'est voulu : la séance précédente ne doit pas laisser la solution dans `journalctl`.

Le reset tue tous les processus de l'utilisateur `student`. Ne le lancez pas pendant une séance.

En mode mot de passe, le SSH de `student` est ouvert aux bots qui testent des mots de passe. Provisionnez le VPS juste avant la séance et détruisez-le juste après. Pas de pare-feu ajouté par les scripts.

Testé uniquement sur un droplet DigitalOcean en Debian 13. Les autres hébergeurs, Debian 12 et Ubuntu 22.04/24.04 ne sont pas testés. Sur DigitalOcean, l'image contient `/etc/ssh/sshd_config.d/50-cloud-init.conf` avec `PasswordAuthentication no` : c'est pour ça que notre fichier s'appelle `00-masterclass.conf`. Chez un autre hébergeur, vérifiez que `check.sh` affiche bien PASS sur la ligne SSH.

Détail technique : l'image disque est remplie avec `nodelalloc`. Sans cette option, ext4 garde quelques blocs en réserve et `df` n'affiche jamais 0 disponible.
