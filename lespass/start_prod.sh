#!/bin/bash
set -e

poetry run python3 manage.py migrate_schemas --executor=multiprocessing
poetry run python3 manage.py install \
  || echo "WARNING: manage.py install a échoué — à relancer manuellement si premier déploiement"
poetry run python3 manage.py collectstatic --noinput

exec poetry run gunicorn TiBillet.wsgi \
  --log-level=info \
  -w 5 -b 0.0.0.0:8002
