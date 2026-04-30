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

### Phase 2 --- Fedow minimal compose (no Nginx, no Traefik)

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

### Phase 3 --- Add Nginx in front of Fedow

**Goal:** Nginx proxies to Fedow Django. Static files are served by
Nginx, not Gunicorn.

**Steps:**

1.  Remove the direct port exposure from `fedow_django`
2.  Add `fedow_nginx` with the nginx config and `./www` volume
3.  Expose port `80` on `fedow_nginx`
4.  `docker compose up`
5.  `curl http://localhost/` --- same response, now through Nginx

**Verify:** `curl http://localhost/static/` returns a static file.

------------------------------------------------------------------------

### Phase 4 --- Lespass Dockerfile

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

### Phase 5 --- Lespass minimal compose (Django + Postgres only)

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

### Phase 6 --- Add Redis and Celery to Lespass

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

### Phase 7 --- Add Memcached and Nginx to Lespass

**Steps:**

1.  Add `lespass_memcached`
2.  Add `lespass_nginx` with the Nginx config
3.  Move port exposure from `lespass_django` to `lespass_nginx`
4.  `docker compose up`

**Verify:** `curl http://localhost/` returns a response through Nginx.

------------------------------------------------------------------------

### Phase 8 --- Wire Lespass and Fedow together

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

### Phase 9 --- Prepare the Coolify deploy

**Goal:** produce a compose file ready to hand to Coolify. No Traefik
needed --- Coolify's built-in Traefik handles routing and TLS through
its UI.

**Steps:**

1.  Replace `build: .` with `image: tibillet/fedow:latest` and
    `image: tibillet/lespass:latest`
2.  Remove all `./:/DjangoFiles` bind mounts (code is baked into the
    image)
3.  Change `start_dev.sh` to `start.sh` in all commands
4.  Remove all Traefik labels from the compose files --- Coolify
    ignores them anyway and generates its own
5.  Remove direct `ports:` exposures --- Coolify routes traffic
    internally
6.  Set all runtime flags to production values in `.env` (`DEBUG=0`,
    `TEST=0`, `DEMO=0`, `STRIPE_TEST=0`, `MIGRATE=0`)
7.  Use named volumes for all persistent data (database, media files)

**Verify:** the compose file is clean, no dev artefacts, no Traefik
labels, no bind mounts.

------------------------------------------------------------------------

### Phase 10 --- Deploy on Coolify

**Goal:** Fedow and Lespass running on the production server, reachable
over HTTPS, with TLS managed by Coolify.

**Steps:**

1.  Deploy Fedow first via Coolify UI --- set the domain
    (`fedow.yourdomain.com`) and paste the Fedow env vars
2.  Confirm Fedow responds at `https://fedow.yourdomain.com/dashboard/`
3.  Set `FEDOW_DOMAIN=fedow.yourdomain.com` in the Lespass env
4.  Deploy Lespass via Coolify UI --- set `MIGRATE=1` for the first
    deploy only
5.  Confirm Lespass responds and Celery worker is alive
6.  Set `MIGRATE=0` in Lespass env and redeploy

**Verify:** `https://yourdomain.com/` and
`https://fedow.yourdomain.com/dashboard/` both work over HTTPS.

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

All Traefik labels in the original TiBillet compose files can be
removed --- Coolify generates its own routing configuration through its
UI.

### Deploy order

1.  Deploy Fedow first (it has no dependencies on Lespass)
2.  Note the Fedow URL (`fedow.yourdomain.com`)
3.  Set `FEDOW_DOMAIN=fedow.yourdomain.com` in Lespass env
4.  Deploy Lespass

### Production `.env` checklist

- [ ] `DEBUG=0`, `TEST=0`, `DEMO=0`
- [ ] `STRIPE_TEST=0`
- [ ] `MIGRATE=0` (set to `1` only for deploys with model changes, then
  reset)
- [ ] Fresh `DJANGO_SECRET`, `SECRET_KEY` --- never reuse dev values
- [ ] Same `FERNET_KEY` in both Fedow and Lespass `.env`
- [ ] Strong `POSTGRES_PASSWORD`
- [ ] Real `DOMAIN`, `FEDOW_DOMAIN`, `SUB`, `META`
- [ ] Valid SMTP credentials
- [ ] Valid live `STRIPE_KEY` and webhook signing secret

