#!/bin/bash
set -e

# Pour Coolify, on a besoin de nettoyer le nommage des variables d'env
export DOMAIN=$FEDOW_DOMAIN
export SECRET_KEY=$FEDOW_SECRET_KEY
# FERNET_KEY est déjà dans l'env, partagé avec Lespass
export STRIPE_KEY=$FEDOW_STRIPE_KEY
export STRIPE_KEY_TEST=$FEDOW_STRIPE_KEY_TEST
export STRIPE_ENDPOINT_SECRET_TEST=$FEDOW_STRIPE_ENDPOINT_SECRET_TEST
export TEST_STRIPE_CONNECT_ACCOUNT=$FEDOW_TEST_STRIPE_CONNECT_ACCOUNT
export STRIPE_TEST=$FEDOW_STRIPE_TEST
export DEBUG=$FEDOW_DEBUG
export TEST=$FEDOW_TEST

poetry run python3 manage.py migrate
poetry run python3 manage.py install
poetry run python3 manage.py collectstatic --noinput

sqlite3 ./database/db.sqlite3 'PRAGMA journal_mode=WAL;'
sqlite3 ./database/db.sqlite3 'PRAGMA synchronous=normal;'
exec poetry run gunicorn fedowallet_django.wsgi \
  --log-level=info \
  -w 5 -b 0.0.0.0:8000
