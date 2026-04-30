#!/bin/bash
set -e

poetry run python3 manage.py migrate
poetry run python3 manage.py install
poetry run python3 manage.py collectstatic --noinput

sqlite3 ./database/db.sqlite3 'PRAGMA journal_mode=WAL;'
sqlite3 ./database/db.sqlite3 'PRAGMA synchronous=normal;'
exec poetry run gunicorn fedowallet_django.wsgi \
  --log-level=info \
  -w 5 -b 0.0.0.0:8000
