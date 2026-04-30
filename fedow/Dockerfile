FROM python:3.10-bullseye
# TODO version à mettre à jour

RUN apt-get update && \
  apt-get upgrade -y && \
  apt-get install -y curl sqlite3

RUN useradd -ms /bin/bash fedow
USER fedow
WORKDIR /home/fedow/Fedow

ENV POETRY_NO_INTERACTION=1
RUN curl -sSL https://install.python-poetry.org | python3 -
ENV PATH="/home/fedow/.local/bin:$PATH"

# Attention : docker build context doit être le dépot deploy

COPY --chown=fedow:fedow ./repo/Fedow/pyproject.toml ./repo/Fedow/poetry.lock ./
RUN poetry install

COPY --chown=fedow:fedow ./repo/Fedow ./
COPY --chown=fedow:fedow ./fedow/start_prod.sh ./

CMD ["bash", "start_prod.sh"]



