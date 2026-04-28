# TiBillet --- Deployment Guide

> Goal: understand the full stack, recreate Docker files from scratch,
> and deploy on a self-hosted PaaS (Coolify or equivalent).

------------------------------------------------------------------------

## 0. Key concepts

This section briefly explains a few background technologies that appear
throughout this document, for readers who are not familiar with them.

At first glance the stack looks like a lot of moving parts. It helps to
group them by role:

- **The core** (unavoidable): Django, a database, Gunicorn. Every
  production Python web app needs these three.
- **The async pair**: Celery + Redis. These two always come together
  the moment you need background tasks. Without them, slow operations
  (PDF generation, emails) would block HTTP requests.
- **The cache**: Memcached. Optional speed optimisation --- the app
  works without it, just slower.
- **The infrastructure glue**: Nginx, Traefik. Something has to serve
  static files and terminate HTTPS. A managed hosting platform like
  Coolify hides most of this from you.

So in practice it is three unavoidable pieces, two that solve one
problem together, and a handful of infrastructure services that a
hosting platform would normally absorb. Once the stack is running, you
rarely touch most of them.

### Docker

Docker is a tool for running applications in **containers** --- isolated
processes that carry everything they need to run (operating system
libraries, language runtime, application code, dependencies) bundled
into a single **image**.

The key distinction:

- An **image** is the recipe: a read-only snapshot built from a
  `Dockerfile`. It never changes.
- A **container** is a running instance of an image: it exists, does
  work, and can be stopped or deleted. You can run many containers from
  the same image simultaneously.

**Docker Compose** is a companion tool that lets you define and start
multiple containers together using a single `docker-compose.yml` file.
Instead of running `docker run ...` with a long list of flags for each
service, you describe all your services, their environment variables,
volumes, and network connections in one file, then start everything
with `docker compose up`.

**Volumes** are how you persist data beyond the lifetime of a
container. By default, anything written inside a container disappears
when the container is removed. A volume mounts a folder from the host
(or a named Docker-managed folder) into the container so that data
survives restarts and rebuilds.

**Networks** let containers talk to each other. By default, containers
are isolated. You add them to the same Docker network so they can reach
each other by container name (e.g. `lespass_django` can connect to
`lespass_postgres` just by using `lespass_postgres` as the hostname).

#### The one-process-per-container convention

A widely followed Docker convention is to run **one process per
container**. This is why you see `fedow_django` and `fedow_nginx` as
two separate containers rather than one container running both Gunicorn
and Nginx.

The reason is practical: each container can be restarted, scaled, and
updated independently. If Nginx crashes, only the Nginx container
restarts --- Gunicorn keeps running and no requests are dropped in
flight. If you want to scale the application under load, you can run
more `fedow_django` containers behind the same Nginx without touching
Nginx at all.

The same logic applies to `lespass_django` and `lespass_celery`: same
image, two containers, two processes, independent lifecycle.

#### One image, multiple purposes

A related pattern: the same image can be used to run **different
containers with different roles**, simply by giving them a different
`command`.

The image defines what is *available* --- the code, the dependencies,
the OS. The command decides what actually *runs* when the container
starts.

In TiBillet, `lespass_django` and `lespass_celery` both use
`tibillet/lespass:latest` but start different processes:

    lespass_django:  command: bash start.sh
    lespass_celery:  command: poetry run celery -A TiBillet worker ...

This makes sense because Celery workers need to import the same Django
models, settings, and business logic as the web server. If they were
separate images you would have to keep them in sync --- same code, same
dependencies, two build pipelines. With one image you build once and
deploy twice.

The general principle: **the image is a toolbox, the command is which
tool you pick up**. You will also see this pattern used for one-off
tasks like running `manage.py migrate` at deploy time --- same image,
throwaway container, different command.

### PostgreSQL

PostgreSQL (often called "Postgres") is a **relational database** ---
the main permanent storage for the application. All data that must
survive a restart (users, tickets, transactions, membership records)
lives here. Unlike Redis, Postgres writes to disk and guarantees that
data is never lost.

TiBillet uses Postgres with a library called `django_tenants`, which
stores each venue's data in a separate **schema** inside the same
database. A schema is like a namespace: the tables exist once per
venue but are fully isolated from each other.

### SQLite

SQLite is a **lightweight relational database** that lives entirely in a
single file on disk. Unlike PostgreSQL, it has no separate server
process --- the application reads and writes the file directly. This
makes it trivially simple to set up: no container, no user management,
no network configuration.

Fedow uses SQLite instead of PostgreSQL because its data (wallets,
token balances) is a single global dataset with relatively low write
traffic. A full Postgres container would be unnecessary overhead.

The trade-off is concurrency: by default, SQLite locks the entire file
on every write, which causes "database is locked" errors under
simultaneous requests. Fedow's `start.sh` works around this by enabling
**WAL mode** (Write-Ahead Log) immediately after startup --- a SQLite
setting that allows reads and writes to happen at the same time without
blocking each other.

### Django

Django is the **Python web framework** that powers both Fedow and
Lespass. It handles HTTP requests, talks to the database, renders
pages, and exposes the REST API. In production it runs inside
**Gunicorn**, a production-grade HTTP server (Django's built-in server
is not safe for production use).

When you see `manage.py migrate` in the start scripts, that is Django
applying database schema changes. When you see `manage.py
collectstatic`, it is copying all static files (CSS, JS, images) into
a single folder so Nginx can serve them directly.

### Gunicorn

Gunicorn is a **production HTTP server for Python**. Django on its own
can serve HTTP requests, but its built-in server is single-threaded and
not safe for production use. Gunicorn wraps Django and runs it as
multiple parallel **worker processes** (typically 4--6), so the
application can handle several requests at the same time.

In the start scripts you will see lines like:

    gunicorn fedowallet_django.wsgi -w 5 -b 0.0.0.0:8000

This means: start 5 worker processes and listen on port 8000. Gunicorn
is never exposed directly to the internet --- Nginx sits in front of it
and forwards requests to it.

### Poetry

Poetry is a **Python dependency manager**. Its job is to install the
exact set of Python libraries the application needs, at the exact
versions that were tested, so the app behaves identically on every
machine and in every Docker build.

You can think of it as the Python equivalent of `npm` (JavaScript) or
`composer` (PHP). It reads two files:

- `pyproject.toml` --- the human-maintained list of dependencies and
  their acceptable version ranges.
- `poetry.lock` --- the machine-generated file that pins every
  dependency (and every dependency's dependency) to an exact version.
  This file is committed to the repository so every build is
  reproducible.

In the Dockerfiles you will see:

    ENV POETRY_NO_INTERACTION=1
    RUN curl -sSL https://install.python-poetry.org | python3 -
    RUN poetry install

This installs Poetry itself, then uses it to install the application's
dependencies. The `POETRY_NO_INTERACTION=1` flag tells Poetry not to
ask any interactive questions during the Docker build.

In the start scripts, commands like `poetry run celery ...` mean "run
this command inside the Poetry-managed virtual environment" --- ensuring
the right library versions are used.

### Celery (not the vegetable)

Celery is a **task queue** for Python applications. The idea is simple:
some operations are too slow or too unreliable to run inside a web
request (generating a PDF, sending an email, calling an external API).
Instead of making the user wait, the web server hands the work off to
Celery, which runs it in the background on a separate process called a
**worker**.

In TiBillet:

- When a cashier closes a shift, Django does not generate the PDF report
  itself --- it sends a message to Celery: *"please generate this PDF
  and email it."*
- Celery workers pick up that message and do the work asynchronously,
  while Django is already free to serve the next request.
- **Redis** acts as the intermediary (called a **broker**): it holds the
  queue of pending tasks until a worker picks them up.
- **Celery Beat** is a scheduler that ships with Celery --- it triggers
  periodic tasks on a schedule (like a cron job), for example sending
  daily membership reminders.

In the compose files you will see `lespass_django` (the web server) and
`lespass_celery` (the background worker) running from the same Docker
image but with different commands. They are two processes doing two
different jobs.

### Redis

Redis is an **in-memory data store** --- think of it as an extremely
fast, temporary notepad that multiple processes can read and write
simultaneously. Because it lives in RAM rather than on disk, it is
orders of magnitude faster than a traditional database like PostgreSQL,
but it is not meant for permanent storage.

In TiBillet, Redis plays two roles:

- **Celery broker:** when Django wants to hand a task to Celery, it
  writes a message to a Redis queue. Celery workers watch that queue
  and pick up tasks as they arrive. Redis is the post office between
  Django and Celery.
- **Result backend:** once a Celery task finishes, it can write its
  result back to Redis so Django can retrieve it later if needed.

You will see it in the compose file as `lespass_redis`. It requires no
configuration beyond the URL passed in `CELERY_BROKER` and
`CELERY_BACKEND`.

### Memcached

Memcached is another **in-memory store**, but with a narrower purpose
than Redis: it is a pure cache. Django uses it to store the results of
expensive operations --- database query results, rendered template
fragments, session data --- so that repeated requests can be answered
from RAM without touching the database again.

It is simpler and faster than Redis for this specific use case, but it
cannot do queues, pub/sub, or persistence. If Memcached disappears,
nothing breaks --- Django just falls back to querying the database
directly and gets slower.

Redis and Memcached sound like they do the same thing, but in TiBillet
they have distinct roles:

- **Memcached** (`lespass_memcached`, `fedow_memcached`) --- Django
  cache, speed optimisation only.
- **Redis** (`lespass_redis`) --- Celery broker, required for async
  tasks to work.

### Reverse proxy

A **proxy** is something that acts on behalf of someone else. A
**reverse proxy** sits in front of one or more servers and intercepts
incoming requests before they reach the application.

The "reverse" distinguishes it from a *forward proxy* (which acts on
behalf of a client, hiding who is making a request) --- a reverse proxy
acts on behalf of the *server*, hiding what is behind it.

In practice, a reverse proxy lets you:

- **Hide internal services** --- the outside world only sees one
  address; the real application servers are never directly reachable.
- **Terminate TLS** --- the proxy handles HTTPS so the application
  behind it can speak plain HTTP internally.
- **Route by domain or path** --- `fedow.example.com` goes to one
  service, `lespass.example.com` goes to another, all on the same
  machine.
- **Serve static files faster** --- the proxy can return files from
  disk without waking up the application at all.

In TiBillet, Nginx is the reverse proxy closest to the application
(Gunicorn), and Traefik is the reverse proxy closest to the internet
(in front of Nginx).

#### Virtual hosting --- one port, many services

You may remember **VirtualHost** from Apache. Traefik uses exactly the
same mechanism under a different name.

The problem: you have one server, one IP address, one port `80` --- but
multiple services (`fedow.tibillet.localhost`,
`lespass.tibillet.localhost`). How does the server know which service
to send each request to?

The answer is the **`Host` header**, a standard part of every HTTP
request since 1997. When your browser requests
`lespass.tibillet.localhost`, it sends:

    GET / HTTP/1.1
    Host: lespass.tibillet.localhost

The reverse proxy reads that header and routes accordingly. All
services share the same port --- the hostname is the key.

This is also how local development works without port numbers: Traefik
listens on port `80`, reads the `Host` header, and forwards to the
right container. Your browser never needs to know which internal port
each service uses.

The underlying HTTP mechanism has not changed in 25 years. What evolved
is how the router learns its routing rules:

  Era          Tool              Config style
  ------------ ----------------- -----------------------------------------
  Late 1990s   Apache VirtualHost   Static files, hand-edited
  2000s-2010s  Nginx `server_name`  Static files, slightly less verbose
  2010s        HAProxy              Static files, more powerful routing
  2015+        Traefik, Caddy       Dynamic --- reads Docker labels automatically

### Nginx

Nginx is a **web server and reverse proxy**. In this stack it sits in
front of Django (Gunicorn) and does two things:

- **Serves static files** (CSS, JS, images) directly from disk,
  without involving Django at all --- much faster.
- **Proxies all other requests** to Gunicorn on its internal port
  (`:8000` for Fedow, `:8002` for Lespass).

Nginx is the only container that is exposed to the outside network.
Django is never reachable directly from the internet.

### Traefik

Traefik is a **reverse proxy and load balancer** that sits in front of
everything. Its job is to receive all incoming HTTPS traffic and route
it to the right Nginx container based on the domain name
(`fedow.yourdomain.com` → `fedow_nginx`,
`lespass.yourdomain.com` → `lespass_nginx`).

It also handles **TLS certificates** automatically: it talks to Let's
Encrypt on your behalf, obtains and renews SSL certificates, and
terminates HTTPS so that the internal containers only need to speak
plain HTTP.

Traefik is configured via **labels** in the `docker-compose.yml` ---
each container declares its own routing rules. This is different from
Nginx, which is configured via static config files.

### Caddy

Caddy is an alternative to Traefik and Nginx combined --- it can act
as both a reverse proxy and an automatic HTTPS server. It is not used
in TiBillet, but it is worth knowing it exists: some self-hosted PaaS
platforms (like Coolify) can use either Traefik or Caddy as their
built-in reverse proxy. For this project, Traefik is the expected
choice.

------------------------------------------------------------------------

## 1. What TiBillet is

TiBillet is a cooperative ticketing, cashless, and membership platform.
It is multi-tenant: a single installation serves multiple venues
("places"), each with its own subdomain and isolated data.

The platform is made of **two Docker images** and several supporting
services.

### Deployment topology

The intended scale model is three tiers:

    Federation level  →  Fedow    (1 instance, shared across all venues and regions)
    Region level      →  Lespass  (1 instance per region, serves all venues as tenants)
    Venue level       →  Tablets  (N browser clients per venue, no local server)

- **One Fedow** per federation manages all wallets, token balances, and
  Stripe Connect.
- **One Lespass** per region is the central server: it holds all tenant
  data, member subscriptions, product catalogues, and cash register
  reports. It must be highly available.
- **POS terminals** (tablets or touchscreens at a venue) are just
  browsers pointing to
  `https://venuename.yourdomain.com/laboutik/caisse/`. No Docker, no
  local server required on the device.

A single venue can have multiple POS terminals simultaneously --- they
all connect to the same Lespass tenant. The Celery workers on Lespass
handle async tasks for all of them (PDF closure reports, emails, NFC
balance checks via Fedow).

### Server requirements

- **vCPU** — 2 minimum
- **RAM** — 4 GB minimum
- **Domain** — wildcard-capable (e.g. `*.tibillet.coop`)
- **Stripe** — account with **Connect** enabled (not just basic Stripe)

------------------------------------------------------------------------

## 2. Architecture overview

    Internet
        │
        ▼
      Traefik  (reverse proxy, TLS termination, port 80/443)
        │
        ├──► fedow_nginx ──► fedow_django:8000
        │
        └──► lespass_nginx ──► lespass_django:8002
                                    │
                               lespass_celery
                                    │
                   ┌────────────────┴───────────────────┐
             lespass_postgres   lespass_redis   lespass_memcached

### The two images

  -------------------------------------------------------------------------
  Image                   Role                Repo
  ----------------------- ------------------- -----------------------------
  `tibillet/fedow`        Federation engine   `github.com/TiBillet/Fedow`
                          --- wallets,        
                          tokens, Stripe      
                          webhooks            

  `tibillet/lespass`      Ticketing + POS     this repo
                          platform (includes  
                          LaBoutik)           
  -------------------------------------------------------------------------

### About LaBoutik

LaBoutik is the point-of-sale (POS) cashless register for NFC card
payments, cash, and credit card transactions. It was originally a
separate Django project in its own repository, deployed as its own
server at each venue. It has since been **merged into Lespass** as a
Django app at `laboutik/`.

In the monorepo model:

- There is **no separate LaBoutik container or image**
- LaBoutik runs inside `lespass_django` and `lespass_celery`
- It shares the same PostgreSQL database via `django_tenants`
- Each tenant (venue) accesses its POS at `/laboutik/caisse/` --- served
  by the central Lespass server
- POS tablets at the venue are just browsers; the server does all the
  work

The merge trades operational simplicity (fewer services to deploy and
maintain) for a stronger dependency on Lespass availability. See the
open questions section at the end of this document.

#### What the old separate-service model looked like

Before the merge, LaBoutik had its own stack per deployment: Postgres,
Redis, Memcached, Gunicorn (`:8000`) and Daphne (`:8001` for
WebSockets). Each venue ran this stack locally, which gave it some
offline autonomy. That model is now replaced by the browser-client
approach described above, but it explains why the official install
documentation (which predates the merge) still describes LaBoutik as a
standalone service.

### Why Fedow exists separately

Fedow manages financial trust between venues: wallets, token federation,
and Stripe Connect. It needs to be a standalone HTTPS service because
LaBoutik terminals (physical cash registers) and Lespass tenants all
call it directly. Keeping it separate also means it can be shared across
multiple Lespass installations.

------------------------------------------------------------------------

## 3. Fedow in detail

### Stack

- **Runtime** — Python 3.10, Django, Gunicorn on `:8000`
- **Database** — **SQLite** (stored in `./database/db.sqlite3`) --- no Postgres container needed
- **Cache** — Memcached
- **Async** — None --- no Celery
- **Static/media** — Served by Nginx from `/www`

### Containers

  -------------------------------------------------------------------------
  Container                Image                     Purpose
  ------------------------ ------------------------- ----------------------
  `fedow_django`           `tibillet/fedow:latest`   Django + Gunicorn,
                                                     runs as user `fedow`

  `fedow_nginx`            `nginx`                   Serves `/static`,
                                                     `/media`; proxies
                                                     everything else to
                                                     `:8000`

  `fedow_memcached`        `memcached:1.6`           Cache
  -------------------------------------------------------------------------

### Production start sequence (`start.sh`)

    1. poetry install
    2. manage.py migrate                  — standard Django migrations on SQLite
    3. manage.py install                  — creates the initial federation asset (run once)
    4. manage.py collectstatic
    5. sqlite3 PRAGMA journal_mode=WAL    — enables write-ahead logging for concurrency
    6. sqlite3 PRAGMA synchronous=normal  — performance tuning
    7. gunicorn fedowallet_django.wsgi -w 5 -b 0.0.0.0:8000

### Fedow Dockerfile (annotated)

``` dockerfile
FROM python:3.10-bullseye

# System packages:
# - sqlite3: required by start.sh to run the PRAGMA commands
# - borgbackup, cron: backup tooling
# - git: unclear if still needed at runtime (worth investigating)
# - nano, curl, iputils-ping: debug/ops tools
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        nano iputils-ping curl borgbackup cron git sqlite3

RUN useradd -ms /bin/bash fedow
USER fedow

ENV POETRY_NO_INTERACTION=1
RUN curl -sSL https://install.python-poetry.org | python3 -
ENV PATH="/home/fedow/.local/bin:$PATH"

COPY --chown=fedow:fedow ./ /home/fedow/Fedow
COPY --chown=fedow:fedow ./bashrc /home/fedow/.bashrc
COPY --chown=fedow:fedow ./backup /backup

WORKDIR /home/fedow/Fedow
RUN poetry install

CMD ["bash", "start.sh"]
```

**Known issues to fix when rebuilding from scratch:**

- The original Dockerfile uses three separate `RUN apt` calls (three
  image layers). Merge into one.
- Add a `.dockerignore` to exclude `database/`, `logs/`, `.env` from the
  build context.
- Verify whether `git` is actually needed at runtime.

### Fedow environment variables

  ----------------------------------------------------------------------
  Variable             Required             Description
  -------------------- -------------------- ----------------------------
  `SECRET_KEY`         yes                  Django secret key

  `FERNET_KEY`         yes                  Shared with Lespass for
                                            inter-service encryption

  `DOMAIN`             yes                  Fedow's own hostname,
                                            e.g. `fedow.tibillet.coop`

  `STRIPE_KEY`         one of               Live Stripe secret key

  `STRIPE_KEY_TEST`    one of               Test Stripe secret key

  `STRIPE_TEST`        yes                  `1` = use test key,
                                            `0` = use live key

  `DEBUG`              yes                  `0` in production

  `TEST`               yes                  `0` in production
  ----------------------------------------------------------------------

### Fedow volumes

- **`/home/fedow/Fedow/database`** — SQLite database file. **Must persist.**
- **`/www`** — Collected static and media files. Recommended to persist.
- **`/logs`** — Gunicorn and Nginx logs. Optional.
- **`/home/fedow/.ssh`** — SSH keys for inter-service access. Persist if needed.

------------------------------------------------------------------------

## 4. Lespass in detail

### Stack

- **Runtime** — Python 3.11, Django, Gunicorn on `:8002`
- **Database** — **PostgreSQL 13** --- multi-tenant via `django_tenants`
- **Cache** — Memcached (tenant-aware keys)
- **Async** — Celery with embedded Beat scheduler, Redis as broker
- **Static/media** — Served by Nginx from `./www`

### Multi-tenancy

Lespass uses `django-tenants`, which stores each tenant's data in a
separate PostgreSQL **schema** (not a separate database). This has
several consequences:

- There is one `POSTGRES_DB` database with many schemas inside it
- Migrations must use `manage.py migrate_schemas` instead of
  `manage.py migrate`
- The `manage.py migrate_schemas --executor=multiprocessing` command
  runs migrations across all schemas in parallel --- this must run on
  every deploy that includes model changes
- The cache key function is `django_tenants.cache.make_key` --- keys are
  automatically namespaced per tenant
- The `public` schema is shared (root landing page, admin, cross-tenant
  federation)

### Containers

  -------------------------------------------------------------------------
  Container                Image                       Purpose
  ------------------------ --------------------------- --------------------
  `lespass_django`         `tibillet/lespass:latest`   Django + Gunicorn, 5
                                                       workers, port
                                                       `:8002`

  `lespass_celery`         same image                  Celery worker + beat
                                                       scheduler (`-B`, 6
                                                       concurrent workers)

  `lespass_nginx`          `nginx:latest`              Proxies to `:8002`,
                                                       WebSocket support,
                                                       serves `./www`

  `lespass_postgres`       `postgres:13-bookworm`      PostgreSQL,
                                                       multi-schema

  `lespass_redis`          `redis:7.2.3-bookworm`      Celery broker and
                                                       result backend

  `lespass_memcached`      `memcached:1.6`             Django cache
  -------------------------------------------------------------------------

`lespass_django` and `lespass_celery` use the **same Docker image** but
different commands:

    lespass_django:  bash start.sh
    lespass_celery:  poetry run celery -A TiBillet worker -l INFO -B --concurrency=6

### Production start sequence (`start.sh`)

    1. poetry install
    2. manage.py collectstatic --no-input
    3. manage.py migrate_schemas --executor=multiprocessing   (only if MIGRATE=1)
    4. gunicorn TiBillet.wsgi -w 5 -b 0.0.0.0:8002

Setting `MIGRATE=1` is controlled by the environment variable. Set it to
`1` only during deploys that include model changes, then set it back to
`0`.

### Lespass Dockerfile (annotated)

``` dockerfile
FROM python:3.11-bullseye

# System packages:
# - postgresql-client: for pg_dump and DB scripts
# - gettext: required by Django's compilemessages (i18n)
# - borgbackup, cron: backup tooling
# - nano, curl, iputils-ping: debug/ops tools
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        postgresql-client nano iputils-ping curl borgbackup cron gettext

RUN useradd -ms /bin/bash tibillet
USER tibillet

ENV POETRY_NO_INTERACTION=1
RUN curl -sSL https://install.python-poetry.org | python3 -
ENV PATH="/home/tibillet/.local/bin:$PATH"

COPY --chown=tibillet:tibillet ./ /DjangoFiles
COPY --chown=tibillet:tibillet ./bashrc /home/tibillet/.bashrc

WORKDIR /DjangoFiles
RUN poetry install

CMD ["bash", "/DjangoFiles/start.sh"]
```

**Things to improve when rebuilding from scratch:**

- Add a `.dockerignore` to exclude `logs/`, `.env`, `__pycache__`,
  `*.pyc`, `database/`
- Verify whether `borgbackup` and `cron` are still actively used or
  legacy

### Lespass environment variables

#### Secrets --- generate fresh for every deployment

  -----------------------------------------------------------------------------------------------------------------------------------------------
  Variable          Description    How to generate
  ----------------- -------------- --------------------------------------------------------------------------------------------------------------
  `DJANGO_SECRET`   Django         `python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"`
                    `SECRET_KEY`   
                    for Lespass    

  `SECRET_KEY`      Django         same command
                    `SECRET_KEY`   
                    for Fedow      

  `FERNET_KEY`      Shared         see command below
                    encryption key 
                    between        
                    Lespass and    
                    Fedow          
  -----------------------------------------------------------------------------------------------------------------------------------------------

> `FERNET_KEY` must be **identical** in both Fedow's and Lespass's
> `.env`. This is how the two services authenticate each other.

The easiest way to generate keys --- this one-liner produces 30 Fernet
key candidates at once, pick one:

``` bash
docker run --rm tibillet/fedow poetry run python3 -c \
  "from cryptography.fernet import Fernet; print('\n'.join([Fernet.generate_key().decode('utf-8') for i in range(0,30)]))"
```

#### Database

- **`POSTGRES_USER`** — PostgreSQL username
- **`POSTGRES_PASSWORD`** — PostgreSQL password --- use a strong random value
- **`POSTGRES_DB`** — PostgreSQL database name

#### Domains

- **`DOMAIN`** — Base domain, no subdomain (e.g. `tibillet.coop`)
- **`FEDOW_DOMAIN`** — Full hostname of Fedow (e.g. `fedow.tibillet.coop`)
- **`SUB`** — Subdomain of the first tenant/place (e.g. `lespass` → `lespass.tibillet.coop`)
- **`META`** — Subdomain of the federated public agenda (e.g. `agenda` → `agenda.tibillet.coop`)
- **`ADDITIONAL_DOMAINS`** — Extra domains for multi-domain SaaS, comma-separated (e.g. `seconddomain.org`)
- **`PUBLIC`** — Display name of the root instance (e.g. `TiBillet Coop.`)

#### Email

- **`EMAIL_HOST`** — SMTP hostname
- **`EMAIL_PORT`** — SMTP port (`465` for SSL)
- **`EMAIL_HOST_USER`** — SMTP username
- **`EMAIL_HOST_PASSWORD`** — SMTP password
- **`ADMIN_EMAIL`** — Receives Django error reports

#### Stripe

- **`STRIPE_KEY`** — Live secret key
- **`STRIPE_KEY_TEST`** — Test secret key
- **`STRIPE_ENDPOINT_SECRET_TEST`** — Webhook signing secret (test)
- **`TEST_STRIPE_CONNECT_ACCOUNT`** — Stripe Connect account ID (test)
- **`STRIPE_TEST`** — `1` = test mode, `0` = live

#### Runtime flags

  ----------------------------------------------------------------------
  Variable           Dev       Prod        Effect when `1`
  ------------------ --------- ----------- -----------------------------
  `DEBUG`            `1`       `0`         Django debug mode, detailed
                                           error pages

  `TEST`             `1`       `0`         Auto-login for admin, skips
                                           TLS cert verification

  `DEMO`             `1`       `0`         Loads demo data on boot

  `STRIPE_TEST`      `1`       `0`         Uses test Stripe keys

  `MIGRATE`          unset     `0` / `1`   Runs `migrate_schemas` on
                                           container start
  ----------------------------------------------------------------------

#### Celery / cache

- **`CELERY_BROKER`** — Redis URL (default: `redis://redis:6379/0`)
- **`CELERY_BACKEND`** — Redis result backend (default: `redis://redis:6379/0`)
- **`TIME_ZONE`** — Django and Celery timezone (default: `UTC`)

#### Backup

- **`BORG_REPO`** — Borg backup repository path or remote (e.g. `user@host:/path/to/repo`)
- **`BORG_PASSPHRASE`** — Encryption passphrase for the Borg repository

Both Fedow and Lespass install `borgbackup` in their Docker images.
These variables configure where backups are sent. Not required to run
the application, but should be set in any production deployment.

### Lespass volumes

- **`/var/lib/postgresql/data`** — PostgreSQL data. **Must persist.**
- **`/DjangoFiles/logs`** — Gunicorn and app logs. Optional.
- **`/www`** — Static and media files. Recommended to persist.

------------------------------------------------------------------------

## 5. Docker networks

Both stacks share two Docker networks:

- **`frontend`** — external (pre-created): Traefik + all Nginx containers
- **`backend`** — internal (per compose): all other containers

The rule is simple: **only Nginx containers touch the `frontend`
network**. Everything else stays in `backend` and is never reachable
from outside.

``` bash
# Create once on the host before starting any stack
docker network create frontend
```

------------------------------------------------------------------------

## 6. Nginx configuration

### Fedow (`nginx/django.conf`)

``` nginx
server {
    listen 80;
    location /static { root /www; }
    location /media  { root /www; }
    location / {
        proxy_pass http://fedow_django:8000;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $host;
        proxy_redirect off;
    }
}
```

### Lespass (`nginx/lespass_dev.conf`)

``` nginx
server {
    listen 80;
    location / {
        proxy_pass http://lespass_django:8002;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;     # WebSocket support
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-IP $remote_addr;
        client_max_body_size 4M;
    }
}
```

The Lespass Nginx config forwards WebSocket upgrade headers because the
POS interface (LaBoutik) uses WebSocket connections.

------------------------------------------------------------------------

## 7. Dev vs Prod --- what changes

### Traefik

  ----------------------------------------------------------------------
               Dev                        Prod
  ------------ -------------------------- ------------------------------
  Location     Defined inside             External, pre-existing, not in
               `docker-compose.yml`       this compose

  TLS          `tls=true`, no cert        Real cert resolvers: `le-ovh`,
               resolver (self-signed)     `le-gandi`, `le-alpn`

  Security     None                       CrowdSec (`crowdsec@file`) on
  middleware                              every router
  ----------------------------------------------------------------------

### Lespass image and code

  ------------------------------------------------------------------------
             Dev                        Prod
  ---------- -------------------------- ----------------------------------
  Build      `build: .` (from local     `image: tibillet/lespass:latest`
             source)                    

  Code mount `./:/DjangoFiles` (live    No mount --- image is
             edits, no rebuild)         self-contained
  ------------------------------------------------------------------------

### Start command

  ------------------------------------------------------------------------
                     Dev                      Prod
  ------------------ ------------------------ ----------------------------
  `lespass_django`   `bash start_dev.sh` ---  `bash start.sh` --- runs
                     creates log files then   collectstatic, migrate if
                     sleeps; you start        `MIGRATE=1`, then Gunicorn
                     Gunicorn manually        

  ------------------------------------------------------------------------

> **Bug in the current `docker-compose.pre-prod.yml`:** both
> `lespass_django` and `lespass_celery` still call `start_dev.sh`
> instead of `start.sh`. This means the container will sleep and never
> start Gunicorn or Celery. Must be fixed before using it in production.

### DNS resolution

  --------------------------------------------------------------------------------------
                  Dev                                   Prod
  --------------- ------------------------------------- --------------------------------
  `extra_hosts`   `*.tibillet.localhost → 172.17.0.1`   `fedow.${DOMAIN} → 172.17.0.1`
                  --- fake local hostnames pointing to  --- only if Fedow is on the same
                  Docker host                           host

  DNS             No real DNS                           Real DNS records pointing to the
                                                        server
  --------------------------------------------------------------------------------------

### Traefik routing on `lespass_nginx`

**Dev** --- one flat rule:

    Host(`$DOMAIN`) || Host(`www.$DOMAIN`) || Host(`agenda.$DOMAIN`) || ...

**Prod** --- three routers, one per TLS strategy:

  ----------------------------------------------------------------------
  Router             Cert resolver                 Coverage
  ------------------ ----------------------------- ---------------------
  `lespass-ovh`      `le-ovh` (DNS challenge via   `*.DOMAIN` wildcard +
                     OVH API)                      apex

  `lespass-gandi`    `le-gandi` (DNS challenge via `*.DOMAIN_GANDI`
                     Gandi API)                    wildcard + apex

  `lespass-simple`   `le-alpn` (ALPN/TLS           single
                     challenge)                    `DOMAIN_SIMPLE` host
  ----------------------------------------------------------------------

If you have one domain and one DNS provider, you only need one router.



## 10. Open questions

These are architectural decisions that affect how the Docker files
should be written. They should be resolved before starting the rebuild.

------------------------------------------------------------------------

### OQ-1 --- Offline resilience for POS terminals

**The question:** what happens when the venue's internet connection
drops?

In the old separate-service model, LaBoutik ran locally at the venue. A
network outage didn't stop the cash register --- it could keep selling
and sync later.

In the monorepo model, every POS action (sale, NFC read, membership
renewal) requires a live connection to the Lespass server. A network
outage stops all POS terminals at the venue.

**Possible answers:**

1.  **Accept the trade-off** --- Lespass must be highly available
    (redundant hosting, good uptime SLA), and venues need reliable
    internet. Simpler deployment, weaker resilience.
2.  **Local Lespass instance per venue** --- deploy a lightweight
    Lespass at the venue (single tenant mode), syncing to the central
    Lespass via Fedow. More complex but offline-capable.
3.  **Progressive Web App (PWA) with local cache** --- the browser
    caches enough data to handle offline sales, queuing them for sync.
    Requires frontend work, no new Docker services.

**Impact on Docker files:** option 1 = no change. Option 2 = a new
minimal compose profile for venue-local deployment. Option 3 = no Docker
change, frontend work only.

------------------------------------------------------------------------

### OQ-2 --- WebSocket server for LaBoutik

In the old separate-service model, LaBoutik ran **Daphne** (an ASGI
server) on port `:8001` specifically for WebSocket connections
(real-time NFC reads, live POS state).

In the monorepo, the Lespass Nginx config already forwards WebSocket
`Upgrade` headers to Gunicorn on `:8002`. Gunicorn can handle WebSockets
to some extent, but Daphne/ASGI is the proper solution for
high-frequency WebSocket traffic.

**The question:** is Gunicorn sufficient for the current LaBoutik
WebSocket usage, or does Lespass need a Daphne process added to the
compose?

**Impact on Docker files:** if Daphne is needed, `lespass_django` would
need to run both Gunicorn (HTTP) and Daphne (WebSocket), or a separate
`lespass_daphne` container would be added.

------------------------------------------------------------------------

## 11. File layout reference

    Fedow/                              (separate repository)
    ├── dockerfile                      # Image: python:3.10, user fedow, app in /home/fedow/Fedow
    ├── docker-compose.yml              # Dev compose (build from source, start_dev.sh)
    ├── start.sh                        # Prod: migrate → install → collectstatic → gunicorn :8000
    ├── start_dev.sh                    # Dev: sleeps, manual start
    ├── nginx/django.conf               # Nginx: static/media from /www, proxy to :8000
    ├── database/                       # SQLite file — must be persisted as a volume
    └── www/                            # Collected static and media files

    Lespass/                            (this repository)
    ├── dockerfile                      # Image: python:3.11, user tibillet, app in /DjangoFiles
    ├── docker-compose.yml              # Dev compose (build from source, Traefik included)
    ├── docker-compose.pre-prod.yml     # Prod compose (external Traefik, real certs, CrowdSec)
    │                                   #   ⚠ still calls start_dev.sh — must be fixed
    ├── start.sh                        # Prod: collectstatic → migrate_schemas → gunicorn :8002
    ├── start_dev.sh                    # Dev: sleeps, manual start
    ├── nginx/
    │   ├── lespass_dev.conf            # Nginx: proxy to :8002, WebSocket headers, 4M upload
    │   └── fedow_nginx.conf            # Nginx: static/media from /www, proxy to :8000
    ├── laboutik/                       # LaBoutik POS app — merged from its own repo
    │   ├── models.py                   # POS models: PointDeVente, CartePrimaire, Table, etc.
    │   ├── views.py                    # DRF ViewSets: Caisse, Paiement, Commande
    │   ├── tasks.py                    # Celery tasks: closure report emails, PDF generation
    │   └── ...
    ├── TiBillet/settings.py            # Django settings (reads all config from os.environ)
    ├── www/                            # Static and media files served by Nginx
    └── logs/                           # Nginx + Gunicorn logs
