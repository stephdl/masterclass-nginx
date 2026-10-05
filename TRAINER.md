# Masterclass nginx : notes du formateur

Ces notes restent dans `/root/masterclass-nginx` (mode 700). L'élève ne doit pas les voir.

L'objectif est la méthode, pas les commandes : observer, lire le journal, trouver la cause, corriger, vérifier. Faites-la répéter à chaque panne.

## Préparation

Sur un VPS jetable (Debian 13 testé), en root :

```
scp -r masterclass-nginx root@VPS:/root/
ssh root@VPS
STUDENT_PASSWORD='mot-de-passe' /root/masterclass-nginx/setup.sh --yes-this-is-a-throwaway-vps
# ou avec une clé : STUDENT_PUBKEY="ssh-ed25519 AAAA... eleve" ...
# ou : /root/masterclass-nginx/setup.sh --yes-this-is-a-throwaway-vps /chemin/eleve.pub
```

Avec un mot de passe, le setup ajoute `/etc/ssh/sshd_config.d/00-masterclass.conf` qui autorise les mots de passe pour `student` seulement. Root reste en clé. Le script ne garde que le hash du mot de passe, et `reset.sh` le remet si l'élève l'a changé.

Le premier setup prend environ une minute (image disque), puis attend que la charge monte. Il finit par `check.sh`.

Avant chaque séance :

```
/root/masterclass-nginx/reset.sh --yes-this-is-a-throwaway-vps
```

Le reset prend environ 4 s. Il tue les sessions de l'élève, restaure le disque, la config nginx, son home, et vide tout le journal système. Il finit par `check.sh`. Si seule la charge est en FAIL (le leurre était arrêté), relancez `check.sh` une minute plus tard.

Le compte élève : `ssh student@VPS`, sudo sans mot de passe.

N'écrivez pas le mot de passe dans `setup.sh`, mettez-le seulement dans la commande.

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

Ce que l'élève voit :

```
$ uptime
 12:16:09 up 21 min,  1 user,  load average: 1.77, 0.69, 0.30
```

Dans `htop` ou `top`, deux processus `report-batch` à 100 % (un par vCPU), NI à 19 :

```
    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
   5733 root      39  19    4488   1592   1308 R 100.0   0.1   0:15.06 report-+
   5734 root      39  19    4488   1592   1308 R 100.0   0.1   0:15.08 report-+
```

```
$ systemctl status report-batch
● report-batch.service - Nightly report batch
     Loaded: loaded (/etc/systemd/system/report-batch.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-10-05 12:15:53 UTC; 26s ago
```

Ce qu'il faut conclure : la charge est réelle mais sans rapport avec nginx. Les processus ont une priorité basse (nice 19), la machine reste réactive. On ne tue rien. On note l'observation et on passe à nginx.

Si l'élève l'arrête quand même (`systemctl stop report-batch`), demandez-lui si le site remarche. Non. Bonne leçon : corriger ce qu'on voit n'est pas corriger la panne.

Indices :
1. Vague : « La machine est occupée. Est-ce que ça explique que le site ne réponde pas ? »
2. Précis : « Regarde la colonne NI. Que veut dire 19 ? Quel service a lancé ces processus ? »
3. Explicite : « C'est un batch sans rapport. Regarde `systemctl status nginx`. »

## Étape 2 : la faute de frappe

Sans sudo, le journal est vide. C'est un bon moment pour parler des droits :

```
$ journalctl -u nginx -e
Hint: You are currently not seeing messages from other users and the system.
      Users in groups 'adm', 'systemd-journal' can see all messages.
      Pass -q to turn off this notice.
-- No entries --
```

Avec sudo :

```
$ sudo systemctl status nginx
× nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled; preset: enabled)
     Active: failed (Result: exit-code) since Mon 2026-10-05 12:15:54 UTC; 24s ago
    Process: 5798 ExecStartPre=/usr/sbin/nginx -t -q -g daemon on; master_process on; (code=exited, status=1/FAILURE)

Oct 05 12:15:54 debian-s-2vcpu-2gb-fra1 nginx[5798]: 2026/10/05 12:15:54 [emerg] 5798#5798: invalid number of arguments in "root" directive in /etc/nginx/conf.d/demo.conf:8
Oct 05 12:15:54 debian-s-2vcpu-2gb-fra1 nginx[5798]: nginx: configuration file /etc/nginx/nginx.conf test failed
Oct 05 12:15:54 debian-s-2vcpu-2gb-fra1 systemd[1]: nginx.service: Control process exited, code=exited, status=1/FAILURE
Oct 05 12:15:54 debian-s-2vcpu-2gb-fra1 systemd[1]: Failed to start nginx.service - A high performance web server and a reverse proxy server.
```

```
$ sudo nginx -t
2026/10/05 12:16:19 [emerg] 5944#5944: invalid number of arguments in "root" directive in /etc/nginx/conf.d/demo.conf:8
nginx: configuration file /etc/nginx/nginx.conf test failed
```

Le piège pédagogique : nginx annonce la ligne 8, mais la faute est ligne 7. Le point-virgule manque à la fin de `root`, donc nginx lit `root /var/www/demo index index.html;` comme une seule directive avec trois arguments.

```
     7	    root /var/www/demo
     8	    index index.html;
```

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

Juste après la correction, une nouvelle erreur apparaît. Elle n'était pas visible avant, car nginx s'arrête à la première erreur de syntaxe.

```
$ sudo nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
2026/10/05 12:16:31 [emerg] 6000#6000: mkdir() "/srv/demo-data/tmp/body" failed (28: No space left on device)
nginx: configuration file /etc/nginx/nginx.conf test failed
```

```
$ sudo systemctl restart nginx
Job for nginx.service failed because the control process exited with error code.
See "systemctl status nginx.service" and "journalctl -xeu nginx.service" for details.
$ sudo journalctl -u nginx -e
Oct 05 12:16:31 debian-s-2vcpu-2gb-fra1 nginx[6004]: 2026/10/05 12:16:31 [emerg] 6004#6004: mkdir() "/srv/demo-data/tmp/body" failed (28: No space left on device)
Oct 05 12:16:31 debian-s-2vcpu-2gb-fra1 nginx[6004]: nginx: configuration file /etc/nginx/nginx.conf test failed
```

Point à faire remarquer : la « syntax is ok ». La première panne est bien réparée. C'est une deuxième panne.

Enquête :

```
$ df -h
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda1        59G  1.5G   55G   3% /
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

$ file /srv/demo-data/backups/2023/site-backup-2023-03-14.tar
/srv/demo-data/backups/2023/site-backup-2023-03-14.tar: POSIX tar archive (GNU)

$ tar tvf /srv/demo-data/backups/2023/site-backup-2023-03-14.tar | head -5
drwxr-xr-x root/root         0 2023-03-14 02:10 ./
drwxr-xr-x root/root         0 2023-03-14 02:10 ./var/
drwxr-xr-x root/root         0 2023-03-14 02:10 ./var/www/
...
```

Le `/` affiche 3 % : un débutant conclut souvent « le disque n'est pas plein ». Faites lire toutes les lignes de `df`. Le chemin du message d'erreur (`/srv/demo-data/...`) dit sur quel disque regarder.

Avant de supprimer, l'élève doit vérifier ce qu'est le fichier : vieux de 2023, une sauvegarde, rien ne l'utilise. Les fichiers de `uploads/` et `exports/` sont légitimes. On n'y touche pas.

Solution :

```
sudo rm /srv/demo-data/backups/2023/site-backup-2023-03-14.tar
df -h /srv/demo-data
sudo systemctl restart nginx
systemctl status nginx
curl -I http://localhost
```

Résultat attendu :

```
/dev/loop0      182M  122K  178M   1% /srv/demo-data

HTTP/1.1 200 OK
Server: nginx
Content-Type: text/html
```

Indices :
1. Vague : « Que veut dire "No space left on device" ? Sur quel disque ? »
2. Précis : « `df -h` montre tous les disques. Puis `du` pour trouver ce qui prend la place. »
3. Explicite : « Une vieille sauvegarde de 2023 remplit `/srv/demo-data`. Vérifie avec `file`, supprime-la, redémarre. »

Fin : demandez la preuve que c'est réparé. « Il a redémarré » ne suffit pas. `curl -I` qui répond 200, oui.

## Réserve : le port 80 occupé

Uniquement une fois le scénario principal réparé (le script refuse sinon) :

```
/root/masterclass-nginx/extra-port80.sh --yes-this-is-a-throwaway-vps on
```

Ce que l'élève voit :

```
$ sudo systemctl status nginx
Oct 05 12:17:05 debian-s-2vcpu-2gb-fra1 nginx[6240]: nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)
Oct 05 12:17:06 debian-s-2vcpu-2gb-fra1 nginx[6240]: nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)
...
Oct 05 12:17:08 debian-s-2vcpu-2gb-fra1 nginx[6240]: nginx: [emerg] still could not bind()
Oct 05 12:17:08 debian-s-2vcpu-2gb-fra1 systemd[1]: Failed to start nginx.service - A high performance web server and a reverse proxy server.

$ sudo nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful

$ sudo ss -ltnp 'sport = :80'
State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
LISTEN 0      5            0.0.0.0:80        0.0.0.0:*    users:(("python3",pid=6232,fd=3))
```

Leçon : `nginx -t` passe, la config est bonne. Le problème est ailleurs. Le service `legacy-dashboard` a `Restart=always` : un `kill` du PID ne suffit pas, il revient. Il faut passer par systemd.

Solution :

```
systemctl status 6232          # retrouve le service à partir du PID
sudo systemctl disable --now legacy-dashboard
sudo systemctl restart nginx
curl -I http://localhost
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

Testé uniquement sur Debian 13 (nginx 1.26.3, 2 vCPU). Debian 12 et Ubuntu 22.04/24.04 ne sont pas testés.

Détail technique : l'image disque est remplie avec `nodelalloc`. Sans cette option, ext4 garde quelques blocs en réserve et `df` n'affiche jamais 0 disponible.
