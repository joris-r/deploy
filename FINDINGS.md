# Findings

Observations à remonter à l'équipe TiBillet.

## Fedow — versions obsolètes dans le Dockerfile

Le `dockerfile` du repo Fedow utilise :

- `python:3.10-bullseye` comme image de base
- **Python 3.10** — en "security only", plus de bugfixes depuis 2023.
  Versions recommandées : 3.12 ou 3.13.
- **Bullseye** (Debian 11) — EOL août 2024. Remplacer par
  **Bookworm** (Debian 12), supporté jusqu'en 2028 en LTS mais EOL en juin 2026
  sinon **Trixie** (Debian 13), EOL en 2028.

Le dockerfile est bien celui utilisé en prod : le `docker-compose.yml`
fait `build: .` (l'option `image: tibillet/fedow:latest` est
commentée). La dernière ligne du compose confirme que c'est ce
dockerfile qui sert à construire et publier l'image sur Docker Hub.

**Action :** signaler à l'équipe et proposer une montée de version
(`python:3.12-bookworm`), en vérifiant d'abord la compatibilité des
dépendances dans `pyproject.toml`.

## Fedow — `git` installé mais inutile

Le Dockerfile installe `git` parmi les paquets système. Une ligne
commentée révèle pourquoi : le code était autrefois cloné depuis
GitHub pendant le build (`RUN git clone ...`). Cette approche a été
abandonnée au profit d'un `COPY`, mais `git` est resté dans la liste
des paquets sans être nettoyé.

**Action :** supprimer `git` des paquets installés pour alléger
l'image.

## Fedow — logs Gunicorn dans un fichier

Le `start.sh` du repo Fedow passe `--log-file` à Gunicorn, ce qui
écrit les logs dans un fichier à l'intérieur du container. En Docker,
la convention est de logger sur stdout/stderr pour que `docker logs`
fonctionne. Un fichier de log non géré grossit indéfiniment et
nécessite un `logrotate` manuel.

**Action :** supprimer `--log-file` de la commande Gunicorn. Les logs
stdout sont gérés automatiquement par Docker avec rotation configurable
(`max-size`, `max-file`).
