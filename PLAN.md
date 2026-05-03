# Rebuild Plan

## 1. Intro

See README.md for general context.

## 2. Step-by-step rebuild plan

The goal is to rewrite every Docker file from scratch, understanding
each line. Work one layer at a time with a working verification at each
step.

### Prerequisites

Before writing anything:

- Docker CLI and Docker Compose installed and working
- Understand the difference between an **image** (recipe) and a
  **container** (running instance)
- Understand **volumes**: named (`fedow_database:`) vs bind mounts
  (`./folder:/container/path`)
- Understand **networks**: why two containers need to be on the same
  network to talk to each other
- Know the basic commands: `docker build`, `docker run`,
  `docker compose up/down/logs`, `docker exec`

------------------------------------------------------------------------

### Phase 1 --- Fedow Dockerfile [TERMINÉE]

**Why start here:** Fedow is simpler (SQLite, no Celery, no Postgres).
Getting it right first gives you a working dependency before touching
Lespass.

**Steps:**

1.  Write a new `dockerfile` from scratch in
    `/home/joris/DEV/tibillet/Fedow/`
2.  Add a `.dockerignore` (exclude `database/`, `logs/`, `.env`,
    `__pycache__`, `*.pyc`)
3.  `docker build -t fedow_django .`
4.  `docker run --rm fedow_django poetry run python manage.py check` --- should pass
    with no errors

**Verify:** the image builds and Django loads without crashing.

------------------------------------------------------------------------

### Phase 2 --- Fedow minimal compose (no Nginx, no Traefik) [TERMINÉE]

**Goal:** get Fedow's Django app to respond on a port, directly, with no
proxy in front.

``` yaml
services:
  fedow_memcached:
    image: memcached:1.6

  fedow_django:
    build: .
    ports:
      - "8000:8000"
    env_file: .env
    command: bash start.sh
```

**Steps:**

1.  Write a minimal `.env` with `SECRET_KEY`, `FERNET_KEY`, `DOMAIN`,
    `STRIPE_TEST=1`, `STRIPE_KEY_TEST`
2.  `docker compose up`
3.  Watch the logs --- confirm `migrate`, `install`, `collectstatic`,
    Gunicorn all succeed
4.  `curl http://localhost:8000/` --- should get a response

**Verify:** Fedow dashboard responds at
`http://localhost:8000/dashboard/`.

------------------------------------------------------------------------

### Phase 3 --- Add Nginx in front of Fedow [TERMINÉE]

**Goal:** Nginx proxies to Fedow Django. Static files are served by
Nginx, not Gunicorn.

**État actuel (2026-04-30) :**

- `fedow/nginx/django.conf` créé (copié depuis le repo Fedow)
- `fedow_nginx` ajouté dans le compose avec le volume bind mount
  `./nginx:/etc/nginx/conf.d`
- `fedow_django` expose encore le port 8000 directement

**Ce qui reste à faire :**

1.  Retirer `ports: 8000:8000` de `fedow_django`
2.  Ajouter un volume nommé `fedow_static` partagé entre
    `fedow_django` (`/home/fedow/Fedow/www`) et `fedow_nginx`
    (`/www`) — nécessaire pour que Nginx serve les fichiers
    générés par `collectstatic`
3.  Déclarer `fedow_static` dans la section `volumes:` du compose
4.  `docker compose up --build`
5.  `curl http://localhost/` --- même réponse, maintenant via Nginx

**Verify:** `curl http://localhost/static/` returns a static file.

------------------------------------------------------------------------

### Phase 4 --- Lespass Dockerfile [TERMINÉE]

**Why now:** Lespass depends on Fedow being reachable. But the image
itself can be built and tested in isolation before wiring them together.

**Steps:**

1.  Write a new `dockerfile` in the Lespass repo root
2.  Add a `.dockerignore` (exclude `logs/`, `.env`, `__pycache__`,
    `*.pyc`, `www/`, `database/`)
3.  `docker build -t lespass-test .`
4.  `docker run --rm lespass-test python manage.py check` --- will fail
    on database connection, but Django itself should load

**Verify:** the image builds cleanly.

------------------------------------------------------------------------

### Phase 5 --- Lespass minimal compose (Django + Postgres only) [TERMINÉE]

**Goal:** get `manage.py migrate_schemas` to run and Django to start,
with no Nginx, no Celery, no Redis.

``` yaml
services:
  lespass_postgres:
    image: postgres:13-bookworm
    env_file: .env

  lespass_django:
    build: .
    ports:
      - "8002:8002"
    env_file: .env
    depends_on:
      - lespass_postgres
    command: bash start.sh
```

**Steps:**

1.  Set `MIGRATE=1` in `.env`
2.  `docker compose up`
3.  Watch the logs --- `migrate_schemas` must complete before Gunicorn
    starts
4.  `curl http://localhost:8002/` --- should get a response (even if
    it's a 404)

**Verify:** Gunicorn is running and the app responds.

------------------------------------------------------------------------

### Phase 6 --- Add Redis and Celery to Lespass [TERMINÉE]

**Goal:** async tasks work.

**Steps:**

1.  Add `lespass_redis` to the compose
2.  Add `lespass_celery` with the Celery command and the same env file
3.  `docker compose up`
4.  Check Celery logs --- should show worker startup and connected to
    Redis
5.  `docker exec lespass_celery poetry run celery -A TiBillet inspect ping`
    --- should return a pong

**Verify:** Celery worker is alive and connected.

------------------------------------------------------------------------

### Phase 7 --- Add Memcached and Nginx to Lespass [TERMINÉE]

**Steps:**

1.  Add `lespass_memcached`
2.  Add `lespass_nginx` with the Nginx config
3.  Move port exposure from `lespass_django` to `lespass_nginx`
4.  `docker compose up`

**Verify:** `curl http://localhost/` returns a response through Nginx.

------------------------------------------------------------------------

### Phase 8 --- Wire Lespass and Fedow together [TERMINÉE]

**Goal:** Lespass can call Fedow's API using `FEDOW_DOMAIN`.

Both stacks must share the same Docker network for this to work locally.
Options:

- Put everything in one `docker-compose.yml` (simplest for dev)
- Use the `frontend` external network and set `extra_hosts` to resolve
  `fedow.yourdomain.localhost → 172.17.0.1`

**Steps:**

1.  Start Fedow compose first
2.  Set `FEDOW_DOMAIN` in Lespass `.env` to Fedow's reachable hostname
3.  Start Lespass compose
4.  Exec into `lespass_django` and call Fedow's health endpoint with
    `curl`

**Verify:** Lespass can reach Fedow over HTTP.

------------------------------------------------------------------------

### Phase 9 --- Compose unique pour Coolify

**Goal:** produire un `docker-compose.yml` unique à la racine de
`deploy/` rassemblant Fedow et Lespass, prêt pour Coolify.

Fedow et Lespass sont couplés (même `FERNET_KEY`, `FEDOW_DOMAIN`
nécessaire) — un seul compose est plus cohérent.

**Ce qu'on garde des composes de dev :**

- `build: context/dockerfile` explicites (nos propres images)
- `start_prod.sh` comme commande de démarrage
- Bind mount `./lespass/www` pour les statiques Lespass (problème
  de permissions avec les volumes nommés)
- Réseau interne unique — plus besoin du réseau externe
  `tibillet_backend` puisque tout est dans le même compose

**Steps:**

1.  Créer `deploy/docker-compose.yml` avec tous les services :
    `fedow_memcached`, `fedow_django`, `fedow_nginx`,
    `lespass_postgres`, `lespass_redis`, `lespass_memcached`,
    `lespass_django`, `lespass_celery`, `lespass_nginx`
2.  Volume nommé pour `lespass_postgres` (données persistantes)
3.  Supprimer le volume `fedow_static` inutile (Fedow ne fait pas
    de `collectstatic`)
4.  Retirer les `ports:` de `fedow_nginx` et `lespass_nginx` —
    Coolify route le trafic en interne
5.  Créer `deploy/.env` à partir des deux `.env` existants
6.  `docker compose up` et vérifier que tout démarre

**Verify:** `docker compose ps` montre tous les services `Up`.

------------------------------------------------------------------------

### Phase 10 --- Deploy on Coolify

**Goal:** Fedow et Lespass en production sur le serveur Coolify,
accessibles en HTTPS, TLS géré par Coolify.

**Contexte :** Coolify utilise son propre Traefik. Il gère le
routage par domaine, les certificats Let's Encrypt, et les réseaux
internes. Pas besoin de labels Traefik dans le compose.

**Steps:**

1.  Pousser le repo `deploy` sur GitHub (fork personnel)
2.  Dans Coolify, créer une nouvelle application de type
    "Docker Compose" pointant sur ce repo
3.  Configurer les variables d'environnement dans l'UI Coolify
    (voir checklist ci-dessous)
4.  Configurer les domaines dans l'UI Coolify :
    - `fedow.yourdomain.com` → `fedow_nginx`
    - `yourdomain.com` et `*.yourdomain.com` → `lespass_nginx`
5.  Premier déploiement — vérifier les logs de migration
6.  Vérifier que Fedow répond sur
    `https://fedow.yourdomain.com/dashboard/`
7.  Vérifier que Lespass répond sur `https://yourdomain.com/`

**Verify:** les deux services répondent en HTTPS.

------------------------------------------------------------------------

## 9. Deploying on Coolify

### Pre-conditions on the host

Nothing special --- Coolify manages its own Traefik instance and
internal networks. You do not need to create a `frontend` network
manually.

### Chosen approach: Coolify's built-in Traefik (Option A)

Since there is already a website running on this Coolify server,
Option A is the only sensible choice. Disabling Coolify's Traefik
(Option B) would take down the existing site and require migrating all
routing manually.

With Option A, Coolify handles everything:

- Routing by domain name
- TLS certificate provisioning and renewal via Let's Encrypt
- Internal networking between containers

### Production `.env` checklist

- [ ] `DEBUG=0`, `TEST=0`, `DEMO=0`
- [ ] `STRIPE_TEST=0`
- [ ] Fresh `DJANGO_SECRET` (Lespass) et `SECRET_KEY` (Fedow) —
  ne jamais réutiliser les valeurs de dev
- [ ] Même `FERNET_KEY` dans Fedow et Lespass
- [ ] `POSTGRES_PASSWORD` fort
- [ ] `DOMAIN`, `FEDOW_DOMAIN`, `SUB`, `META` réels
- [ ] Credentials SMTP valides
- [ ] `STRIPE_KEY` live et webhook signing secret valides

