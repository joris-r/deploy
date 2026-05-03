# Findings

Observations à remonter à l'équipe TiBillet.

## Fedow — versions obsolètes dans le Dockerfile

Le `dockerfile` du repo Fedow utilise :

- `python:3.10-bullseye` comme image de base
- **Python 3.10** — en "security only", plus de bugfixes depuis 2023.
  Versions recommandées : 3.12 ou 3.13.
- **Bullseye** (Debian 11) — EOL août 2024. Remplacer par
  **Trixie** (Debian 13) — les images officielles `memcached` et
  `nginx` sont déjà sur Trixie, autant aligner Fedow pour cohérence.

Le dockerfile est bien celui utilisé en prod : le `docker-compose.yml`
fait `build: .` (l'option `image: tibillet/fedow:latest` est
commentée). La dernière ligne du compose confirme que c'est ce
dockerfile qui sert à construire et publier l'image sur Docker Hub.

**Action :** signaler à l'équipe et proposer une montée de version
(`python:3.12-trixie`), en vérifiant d'abord la compatibilité des
dépendances dans `pyproject.toml`.

## Fedow — `git` installé mais inutile

Le Dockerfile installe `git` parmi les paquets système. Une ligne
commentée révèle pourquoi : le code était autrefois cloné depuis
GitHub pendant le build (`RUN git clone ...`). Cette approche a été
abandonnée au profit d'un `COPY`, mais `git` est resté dans la liste
des paquets sans être nettoyé.

**Action :** supprimer `git` des paquets installés pour alléger
l'image.

## Fedow — `exec` manquant devant Gunicorn

Le `start.sh` du repo Fedow lance Gunicorn sans `exec` :

```bash
poetry run gunicorn ...
```

Sans `exec`, bash reste PID 1 et Gunicorn tourne comme processus
enfant. Quand Docker envoie `SIGTERM` pour arrêter le conteneur,
bash l'ignore et Gunicorn ne le reçoit jamais. Docker attend le
timeout puis envoie `SIGKILL` — arrêt brutal sans graceful shutdown.

**Correction :**

```bash
exec poetry run gunicorn ...
```

`exec` remplace bash par Gunicorn qui devient PID 1 et reçoit
directement les signaux.

**Action :** ajouter `exec` devant la commande Gunicorn dans
`start.sh`.

## Fedow — image Nginx sans version dans le compose

Le `docker-compose.yml` du repo Fedow utilise `image: nginx` sans
numéro de version, ce qui équivaut à `latest`. Un `docker compose
pull` peut silencieusement mettre à jour Nginx vers une version
non testée et casser la configuration.

**Action :** épingler une version explicite, ex. `image: nginx:1.30`.

## Lespass — `exec` manquant devant Gunicorn

Même problème que Fedow : le `start.sh` du repo Lespass lance
Gunicorn sans `exec`, bash reste PID 1 et les signaux Docker ne
sont pas transmis correctement.

**Action :** ajouter `exec` devant la commande Gunicorn dans
`start.sh`.

## Fedow — logs dans des fichiers (Gunicorn et Nginx)

Le `start.sh` passe `--log-file` à Gunicorn, et la config Nginx
écrit `access_log` et `error_log` dans `/logs/`. En Docker, la
convention est de logger sur stdout/stderr pour que `docker logs`
fonctionne. Des fichiers de log non gérés grossissent indéfiniment
et nécessitent un `logrotate` manuel.

**Action :**
- Supprimer `--log-file` de la commande Gunicorn dans `start.sh`
- Remplacer les directives `access_log` et `error_log` dans la
  config Nginx par `access_log /dev/stdout;` et
  `error_log /dev/stderr;`

Les logs stdout sont gérés automatiquement par Docker avec rotation
configurable (`max-size`, `max-file`).

## Lespass — config Django logging écrit dans des fichiers

Le handler `logfile` dans `settings.py` écrit dans
`/DjangoFiles/logs/Djangologfile` via un `RotatingFileHandler`.
Il est utilisé par le logger `import_export`, ce qui force Django à
créer ce fichier au démarrage — même si le logger `root` n'utilise
que `console`.

En Docker, la convention est de logger sur stdout/stderr. Des fichiers
de log dans le container grossissent indéfiniment et ne sont pas
visibles via `docker logs`.

**Action :** supprimer le handler `logfile` et `weasyprint` de
`settings.py` et faire pointer tous les loggers vers `console`
uniquement.

## Lespass — variable d'environnement `SECRET_KEY` mal nommée

Django utilise conventionnellement `SECRET_KEY` comme nom de variable
d'environnement. Lespass la lit sous le nom `DJANGO_SECRET`
(`settings.py` : `os.environ.get('DJANGO_SECRET')`), ce qui surprend
tout opérateur habitué à la convention Django et casse l'intégration
avec des outils qui injectent `SECRET_KEY` automatiquement.

**Action :** renommer en `SECRET_KEY` dans `settings.py`.
