# Problèmes ouverts




## 1. Build lent sur Coolify

Le serveur Coolify est peu puissant. Chaque déploiement
déclenche un build complet des images Django (Fedow et
Lespass) sur ce serveur, ce qui rend la boucle de travail
très lente.

**Ramifications :**
- Itérer sur la configuration est pénible
- Un serveur de prod ne devrait pas être sollicité pour
  compiler du code
- Le build local est bien plus rapide mais le workflow
  pour publier des images n'est pas en place


## 2. Bind mounts et permissions root [CORRIGÉ le 2026-05-04]

Les bind mounts actuels créent des fichiers appartenant à
root sur le host :

- `./lespass/www:/DjangoFiles/www` — Django écrit ses
  fichiers statiques ici
- `./lespass/www:/www` — Nginx lit ces mêmes fichiers

Après chaque déploiement, un `chown` manuel est nécessaire
sur le serveur pour que Django puisse écrire. Ce n'est pas
acceptable en production.

**Ramifications :**
- Chaque redéploiement casse les permissions
- Impossible d'automatiser complètement le déploiement
- Lié au problème 1 : si le déploiement est fréquent,
  l'intervention manuelle l'est aussi


## 3. Conf Nginx montée par bind mount [CORRIGÉ le 2026-05-04]

Les fichiers de configuration Nginx sont montés par bind
mount :

- `./fedow/nginx:/etc/nginx/conf.d`
- `./lespass/nginx:/etc/nginx/conf.d`

En Phase 10, ces fichiers étaient absents sur le serveur
Coolify et ont dû être recopiés à la main. La cause exacte
n'est pas élucidée (chemin de travail Coolify différent ?).

**Ramifications :**
- La configuration Nginx ne survit pas à un redéploiement
  propre
- Intervention manuelle nécessaire sur le serveur
- Lié au problème 2 : l'objectif est zéro bind mount


## 4. Variables d'environnement mal documentées

Il n'existe pas de document de référence unique couvrant
toutes les variables nécessaires pour faire tourner Fedow
et Lespass ensemble.

**Problèmes connus :**
- Certaines variables ont le même nom dans les deux
  services mais des valeurs différentes (`DOMAIN`,
  `SECRET_KEY`, `DEBUG`, `STRIPE_KEY`, etc.)
- Un contournement dans `fedow/start_prod.sh` relit des
  variables préfixées `FEDOW_*` — ce n'est pas documenté
- On ne sait pas quelles variables sont vraiment
  obligatoires vs optionnelles en production

**Inconnues fonctionnelles :**
- Fedow et Lespass partagent-ils le même compte Stripe,
  ou faut-il deux comptes distincts ?
- Lespass peut-il démarrer sans credentials Stripe valides
  si on n'utilise pas le paiement ?
- Quelles variables sont spécifiques à un tenant, et
  lesquelles sont globales à l'installation ?
- `FEDOW_DOMAIN` est une variable clé qui apparaît dans
  les deux problèmes : sa nature (URL publique ou interne)
  conditionne à la fois la documentation des variables et
  l'architecture réseau (voir problème 5)

**Ressource à explorer :**
La documentation officielle d'installation TiBillet
https://tibillet.org/fr/docs/install/docker_install/ —
à relire avec la compréhension Docker acquise durant ce
projet. Elle répondra peut-être aux questions sur les
variables d'environnement, les tenants, et la séquence
de mise en service.


## 5. Architecture réseau de Fedow : exposition externe

Fedow est actuellement exposé sur un domaine public
(`fedow.tibillet.intra.lafab.org`). Mais on ne sait pas
si c'est nécessaire.

**Questions ouvertes :**
- Lespass appelle-t-il Fedow via une URL publique, ou
  pourrait-il utiliser le nom de service Docker interne
  (`http://fedow_django:8000`) ?
- D'autres clients appellent-ils Fedow directement
  (application mobile, service tiers) ?
- `FEDOW_DOMAIN` dans les variables Lespass : est-ce une
  URL publique ou un nom de service interne ? La réponse
  conditionne toute l'architecture réseau.
- On ne sait pas si `FEDOW_DOMAIN` est utilisé uniquement
  au démarrage (handshake, enregistrement) ou à chaque
  requête. Si c'est seulement au démarrage, une URL
  interne suffit même si Fedow est exposé publiquement
  par ailleurs.

**Ramifications :**
- Si Fedow peut rester interne, il n'a pas besoin de
  domaine public, de Nginx exposé, ni de certificat TLS
- Cela simplifierait l'architecture et réduirait la
  surface d'attaque


## 6. Gestion des tenants non documentée

Lespass est une application multi-tenant. On ne sait pas :

- Comment créer un tenant après le premier déploiement
- Comment fonctionne le tenant public et à quoi il sert
- Quelle est la séquence de mise en service complète
  (étapes admin, création d'organisation, paramétrage
  initial)
- Si certaines de ces étapes dépendent de Fedow ou de
  Stripe

**Ramifications :**
- On ne peut pas valider que le déploiement est
  fonctionnellement correct, seulement que les services
  démarrent
- Impossible de planifier le déploiement pour La Fabrique
  sans comprendre cette séquence


## 7. Let's Encrypt ne fonctionne pas

Traefik ne peut pas résoudre `acme-v02.api.letsencrypt.org`
depuis ses containers sur le serveur Coolify. Les services
répondent en HTTPS avec un certificat autosigné.

**Ramifications :**
- Les navigateurs affichent une alerte de sécurité
- Pas utilisable par des utilisateurs finaux en l'état
- La cause (problème DNS interne Docker sur ce serveur)
  n'est pas élucidée
- Le problème touche aussi le site web de La Fabrique
  hébergé sur le même serveur Coolify — c'est donc un
  problème global au serveur, pas spécifique à TiBillet
- Ressources à explorer :
  - https://lumadock.com/tutorials/coolify-ssl
  - https://coolify.io/docs/troubleshoot/dns-and-domains/lets-encrypt-not-working


## 9. Logs : notre déploiement ne respecte pas l'approche upstream

Les dépôts Fedow et Lespass écrivent leurs logs dans des
fichiers (`logs/`). Notre déploiement a modifié ce
comportement pour logger sur stdout, ce qui casse la
convention prévue par les dépôts.

**Conséquences :**
- Le répertoire `logs/` prévu par les dépôts est inutilisé
- Si un futur changement upstream réintroduit des logs
  fichiers, notre deploy ne sera pas prêt
- Tant que les logs vont sur stdout, `docker logs` et
  Coolify fonctionnent — mais c'est une divergence avec
  upstream

**Décision actuelle :** revenir à l'approche des dépôts
(logs dans des fichiers). Cela implique de s'assurer que
le répertoire `logs/` est correctement initialisé dans
les images avec la bonne ownership, et de le déclarer
comme volume nommé dans le compose.

Voir FINDINGS.md pour la note à remonter à l'équipe
TiBillet sur le sujet.


## 8. Pas de document de planification pour La Fabrique

Le PLAN.md couvre la construction technique générale de la
stack. Il n'existe pas de document centré sur le cas
concret :

- Un seul tenant pour l'association La Fabrique
- Usage du module de réservation de ressources
- Sans paiement dans un premier temps
- Domaines réels, variables d'env réelles, séquence de
  mise en service, tests à effectuer

Ce document est nécessaire pour piloter la mise en
production effective.

**Contexte connexe :**
Le déploiement de La Fabrique s'inscrit dans un effort plus
large qui inclut aussi une nouvelle version du site web de
l'association, hébergée sur le même serveur Coolify. Ce
projet est déjà en cours séparément. Il partage deux
problèmes avec la stack TiBillet :

- Le problème Let's Encrypt (problème 7) — c'est un
  problème global au serveur
- Des temps de build lents — le site web a un déploiement
  automatisé par git qui déclenche un build sur le serveur
  à chaque push, avec les mêmes lenteurs que TiBillet

## 11. Postgres pas prêt au démarrage de Lespass

`depends_on: lespass_postgres` garantit que le container
Postgres est démarré, pas qu'il est prêt à accepter des
connexions. Postgres prend quelques secondes à s'initialiser,
ce qui provoque des erreurs de connexion au premier
démarrage de `lespass_django`.

La solution est d'utiliser un `healthcheck` sur
`lespass_postgres` et une condition `service_healthy` dans
le `depends_on` de `lespass_django` :

```yaml
lespass_postgres:
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U postgres"]
    interval: 5s
    timeout: 5s
    retries: 5

lespass_django:
  depends_on:
    lespass_postgres:
      condition: service_healthy
```


## 10. Variables d'environnement : `env_file` incompatible avec Coolify

Le `docker-compose.yml` utilise `env_file:` pour pointer
vers des fichiers `.env` locaux :

```yaml
fedow_django:
  env_file: ./fedow/.env
```

Ces fichiers sont dans le `.gitignore` et ne sont jamais
commitées. Coolify ne les lit pas et ne les gère pas.
En production les variables viennent exclusivement de
l'interface Coolify — le `env_file:` est silencieusement
ignoré. On a donc deux sources de vérité selon
l'environnement.

Coolify détecte automatiquement les variables déclarées
avec `environment:` dans le compose et pré-remplit son
interface avec leurs noms. Ce serait bien plus adapté :

```yaml
fedow_django:
  environment:
    - SECRET_KEY=
    - DOMAIN=
    - ...
```

**Ramifications :**
- Le dev local et la prod ne fonctionnent pas de la même
  façon, ce qui est une source d'erreurs
- Avec `environment:`, le compose devient aussi une
  documentation vivante des variables nécessaires
- Lié au problème 4 (variables mal documentées) : un
  `environment:` exhaustif dans le compose serait un
  premier pas vers ce document de référence
