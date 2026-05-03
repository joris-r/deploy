#!/bin/bash
set -e

# TODO pour le moment je ne charge pas le fichier VERSION
# On va migrer systématiquement

poetry run python3 manage.py migrate_schemas --executor=multiprocessing
poetry run python3 manage.py collectstatic --noinput

exec poetry run gunicorn TiBillet.wsgi \
  --log-level=info \
  -w 5 -b 0.0.0.0:8002