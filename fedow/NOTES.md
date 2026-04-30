# Notes sur le repo Fedow

## Fichiers importants

- `dockerfile` — image de base, dépendances système, install Poetry
- `docker-compose.yml` — orchestration dev (build local, volumes,
  réseau)
- `env_example` — liste des variables d'environnement attendues
- `pyproject.toml` — dépendances Python gérées par Poetry
- `start.sh` — script de démarrage prod (migrate, collectstatic,
  PRAGMA sqlite, gunicorn)
- `start_dev.sh` — script de démarrage dev : fait juste `sleep
  infinity`, le dev lance tout à la main via `docker exec`
- `bashrc` — aliases de confort pour le dev interactif (collect,
  runserver, gunicorn...). Chargé manuellement, pas utilisé par
  `start.sh`.
- `nginx/django.conf` — config Nginx : sert `/static` et `/media`
  depuis `/www`, proxifie tout le reste vers Gunicorn sur `:8000`

## Structure Django

- `fedowallet_django/` — package de configuration Django (settings,
  urls, wsgi, asgi). Généré par `django-admin startproject`.
- `fedow_core/` — app métier principale : modèles, vues, API REST,
  serializers, permissions
- `fedow_dashboard/` — interface d'administration web
- `manage.py` — point d'entrée Django standard
- `database/db.sqlite3` — base SQLite, chemin défini dans
  `settings.py` : `BASE_DIR / database/db.sqlite3`, soit
  `/home/fedow/Fedow/database/db.sqlite3`

## Variables d'environnement

### Obligatoires

- `SECRET_KEY` — clé secrète Django. Exactement **50 caractères**.
  Générer avec `python -c "from django.core.management.utils import
  get_random_secret_key; print(get_random_secret_key())"`
- `FERNET_KEY` — clé de chiffrement partagée avec Lespass.
  Exactement **44 caractères**. Générer avec
  `manage.py generate_fernet`. **Doit être identique** dans les
  `.env` de Fedow et Lespass.
- `DOMAIN` — hostname complet de Fedow, ex. `fedow.tibillet.coop`

### Stripe — une des deux clés obligatoire en prod

- `STRIPE_KEY` — clé live Stripe
- `STRIPE_KEY_TEST` — clé de test Stripe
- `STRIPE_TEST=1` — utilise la clé de test (mettre `0` en prod)

### Optionnelles

- `SENTRY_DNS` — URL Sentry pour le monitoring d'erreurs. Non
  documenté dans `env_example` mais présent dans `settings.py`.
  Activé automatiquement quand `DEBUG=0`.

### Dev uniquement (ne pas mettre à 1 en prod)

- `DEBUG=0` — en prod obligatoirement, sinon stacktraces visibles
- `TEST=0` — active l'auto-login et désactive la vérification TLS.
  Active aussi le cache local (LocMemCache) à la place de Memcached.
- `STRIPE_ENDPOINT_SECRET_TEST` — webhook Stripe de test

## Notes

- Memcached est attendu au hostname `memcached` (alias défini par
  `links:` dans le compose, pas `fedow_memcached`).
- La base SQLite est créée par `manage.py migrate` au premier
  démarrage. Les PRAGMA WAL sont appliqués juste après dans
  `start.sh`.
- `git` est installé dans l'image mais inutile — vestige d'une
  ancienne approche où le code était cloné pendant le build.
- Postgres est commenté dans `settings.py` — Fedow a envisagé une
  migration mais utilise SQLite uniquement pour l'instant.
