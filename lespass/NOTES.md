# Notes sur le repo Lespass

## Fichiers importants

- `dockerfile` — image de base, dépendances système, install Poetry
- `docker-compose.yml` — orchestration dev (build local, volumes,
  réseau)
- `env_example` — liste des variables d'environnement attendues
- `pyproject.toml` — dépendances Python gérées par Poetry
- `start.sh` — script de démarrage prod (migrate_schemas,
  collectstatic, gunicorn)
- `start_dev.sh` — script de démarrage dev
- `nginx/` et `nginx_prod/` — configs Nginx
- `VERSION` — fichier de variables shell : `VERSION` (numéro de
  version) et `MIGRATE` (0/1). Géré manuellement, pas automatique.

## Structure Django

- `TiBillet/` — package de configuration Django (settings, urls,
  wsgi, asgi). Généré par `django-admin startproject`.
- `BaseBillet/` — app métier principale
- `MetaBillet/` — agenda fédéré multi-tenant
- `manage.py` — point d'entrée Django standard
- Base de données PostgreSQL — multi-tenant via `django-tenants`,
  un schema Postgres par lieu. Migrations via `migrate_schemas`.
- Static files : `www/static/`, media : `www/media/`
- Logs applicatifs Django : `logs/Djangologfile` (voir FINDINGS.md)

## Architecture multi-tenant

Lespass utilise `django-tenants` : une seule instance Django sert
plusieurs lieux. Chaque lieu a son propre schema PostgreSQL.
Le routage se fait par sous-domaine :
`lieu1.tibillet.coop` → schema `lieu1`.

La migration utilise `migrate_schemas --executor=multiprocessing`
et non `migrate` — elle applique les migrations sur tous les schemas.

## Variables d'environnement

### Obligatoires

- `DJANGO_SECRET` — clé secrète Django. Attention : nommée
  `DJANGO_SECRET` et non `SECRET_KEY` (convention Django standard).
  Générer avec `python -c "from django.core.management.utils import
  get_random_secret_key; print(get_random_secret_key())"`
- `FERNET_KEY` — clé de chiffrement partagée avec Fedow.
  **Doit être identique** dans les `.env` de Fedow et Lespass.
  Générer avec `manage.py generate_fernet` (côté Fedow).
- `DOMAIN` — domaine racine sans sous-domaine, ex. `tibillet.coop`
- `SUB` — sous-domaine de la première instance, ex. `lespass`
  → accessible sur `lespass.tibillet.coop`
- `META` — sous-domaine de l'agenda fédéré, ex. `agenda`
  → accessible sur `agenda.tibillet.coop`
- `POSTGRES_DB` — nom de la base de données
- `POSTGRES_USER` — utilisateur PostgreSQL
- `POSTGRES_PASSWORD` — mot de passe PostgreSQL

### Obligatoires pour l'initialisation (`manage.py install`)

- `ADMIN_EMAIL` — email du compte admin créé au premier démarrage
- `FEDOW_DOMAIN` — domaine complet de Fedow,
  ex. `fedow.tibillet.coop`
- `PUBLIC` — nom de l'instance racine, ex. `TiBillet Coop.`

### Stripe — nécessaire en prod

- `STRIPE_KEY` — clé live Stripe
- `STRIPE_KEY_TEST` — clé de test Stripe
- `STRIPE_TEST=1` — utilise la clé de test (mettre `0` en prod)
- `STRIPE_ENDPOINT_SECRET_TEST` — webhook Stripe de test

### Services externes

- `CELERY_BROKER` — URL Redis pour Celery, défaut :
  `redis://redis:6379/0`
- `CELERY_BACKEND` — URL Redis pour les résultats Celery, défaut :
  `redis://redis:6379/0`
- `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_HOST_USER`,
  `EMAIL_HOST_PASSWORD`, `DEFAULT_FROM_EMAIL`, `EMAIL_USE_TLS`,
  `EMAIL_USE_SSL` — config SMTP pour les emails transactionnels
- `SENTRY_DNS` — URL Sentry pour le monitoring d'erreurs.
  Activé automatiquement quand `DEBUG=0`.

### OAuth (optionnel)

- `OAUTH_NAME`, `OAUTH_CLIENT_ID`, `OAUTH_CLIENT_SECRET`,
  `OAUTH_ACCESS_TOKEN_URL`, `OAUTH_AUTHORIZE_URL`, `OAUTH_BASE_URL`

### Optionnelles

- `ADDITIONAL_DOMAINS` — domaines supplémentaires séparés par
  virgule, pour le modèle SaaS
- `LANGUAGE_CODE` — défaut `en`
- `TIME_ZONE` — défaut `UTC`

### Dev uniquement (ne pas mettre à 1 en prod)

- `DEBUG=0` — en prod obligatoirement
- `TEST=0` — active l'auto-login et désactive la vérification TLS
- `DEMO=0` — charge des données de démonstration

## Couplage avec Fedow

Lespass et Fedow forment une **installation couplée** — ils ne peuvent
pas être déployés indépendamment :

- La `FERNET_KEY` est générée côté Fedow (`manage.py generate_fernet`)
  puis copiée dans le `.env` de Lespass. Elle sert à chiffrer les
  clés API échangées entre les deux services et stockées en base.
- `FEDOW_DOMAIN` doit pointer vers l'instance Fedow en cours
  d'exécution.
- Les deux services doivent être up et partager la même clé pour que
  l'intégration fonctionne.

## Notes

- PostgreSQL est attendu au hostname `postgres` (défaut dans
  `settings.py` via `POSTGRES_HOST`).
- Redis est attendu au hostname `redis` (défaut Celery broker).
- La commande `manage.py install` crée les tenants publics et
  l'admin au premier démarrage. Elle nécessite `ADMIN_EMAIL`,
  `FEDOW_DOMAIN` et `PUBLIC`.
- `git` n'est pas nécessaire dans l'image — le code est copié
  via `COPY` dans le Dockerfile.
