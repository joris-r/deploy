FROM python:3.11-bullseye
# TODO version à mettre à jour

RUN apt-get update && \
  apt-get upgrade -y && \
  apt-get install -y curl && \
  apt-get install -y --no-install-recommends postgresql-client

RUN useradd -ms /bin/bash tibillet
USER tibillet
WORKDIR /DjangoFiles

# Attention : docker build context doit être le dépot deploy
ARG LESPASS_SRC=./repo/Lespass

# Python
ENV POETRY_NO_INTERACTION=1
RUN curl -sSL https://install.python-poetry.org | python3 -
ENV PATH="/home/tibillet/.local/bin:$PATH"
COPY --chown=tibillet:tibillet ${LESPASS_SRC}/pyproject.toml ${LESPASS_SRC}/poetry.lock ./
RUN poetry install

# Lespass
COPY --chown=tibillet:tibillet ${LESPASS_SRC}/ ./
RUN mkdir -p logs

# Spécifique à ce dépot deploy
COPY --chown=tibillet:tibillet ./lespass/start_prod.sh ./

CMD ["bash", "start_prod.sh"]
