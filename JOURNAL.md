# Journal


## 2026-04-28

J'ai généré un plan avec Claude pour

1. Progresser sur le déployement de service web avec les
  technologies Docker
2. Comprendre la stack de TiBillet

J'ai fait un exercice préliminaire sur docker.

Modèle mental de docker : sert à isoler un service / process.
C'est comme des boites, on relie les boites par des tuyaux
indépendants. Les vraies données sont dans des volumes nommés
(BDD, donnée utilisateurs).

Les images sont des empilage de couches immutables (chaque RUN / COPY
en fabrique une). Il y a ordre : mettre à jour une couche invalide
toute celle baties par dessus. Les couches sont partagées entre
les images. Un Dockerfile = recette pour construire une image.

Un container, c'est une image en train de s'exécuter pour cela
il y a une couche de fichier mutable en plus.
Un container est principalement définit par cette couche mutable.

En plus des tuyaux (réseau), on peut aussi avoir des volumes qui
peuvent partager des répertoire de fichier entre les boites
mais aussi sur le système hotes.

Le docker compose orchestre la création et le lancement des containers,
les réseau, les volumes.
Il définit des services nommés (donne un DNS automatique).
Les conteneurs sont attaché aux réseaux et au volumes.


## 2026-04-29 - Début Phase 1 --- Fedow Dockerfile


Un `Dockerfile` est un script linéaire. Chaque ligne fabrique un layer
dans l'image. Regle : ce qui change rarement en haut.

Les multi-stage build permettent de jeter les layer de constructions.
Voir `FROM <image pour build> AS builder`
... puis
`FROM <image pour run>`
`COPY --from=builder ...`


Toujour en premier `FROM <image>`
  layer de base, en général récupéré du Hub

Exécuter une commande shell `RUN <cmd>`

Copier des fichier depuis l'host `COPY <from host> <to>`
  le chemin host est relatif au **contexte de build**
  voir `docker build -f <chemin/vers/Dockerfile> <contexte>`
  on peut mettre plusieurs `<from host>` mais attention
  Docker copie chaque source en préservant son nom de fichier
  dans le répertoire destination — mais pas son chemin !
  De plus `dir` ou `dir/` comme source copie le contenu de dir mais
  pas le répertoire en lui même.

`WORKDIR` définit un répertoire de travail pour la suite

`ENV` définit une var d'env.

`USER` change l'utilisateur (à créer comme d'habitude avant)

toujours à la fin `CMD` la commande principale qui défini
ce que fait le container (modifiable avec docker-compose)


                        * * *

Pour l'étape de build, c'est à dire de production d'une image.
la commande est `docker build -t <tag> -f <dockerfile> <context>`
avec

- `<tag>` le "nom" donné à l'image
- `<dockerfile>` les instruction de créations, fichier Dockerfile (convention)
- `<context>` le répertoire de travail, les chemins des  `COPY` y sont relatif 

Attention, tout le context est envoyé au deamon docker. Cela peut le ralentir.
On peut écrire un `.dockerignore` qui doit être dans le contexte
afin d'exclure les fichiers qui ne sont nécessaire au build.


Pour la conception d'une image, il faut bien comprendre qu'il y a une frontière
entre la construction de l'image (il faut collecter en une fois toutes les ressources
nécessaire au fonctionement du service) et la configuration / les scripts du 
containter qui doivent être capable de gérer le cycle de vie. La configuration
du service se fait par des variables d'environnement qui doivent être injectée
avant les exécutions du conteneurs.
De ces variables le service dans l'image va pouvoir se configurer. Il y aura
également des migrations, c'est à dire qu'on va changer la version de l'image
et il faudra mettre à jour si nécessaire le contenu des volumes persistants
(nommés) qui contiennent typiquement la base de donnée.

---------------------------------------------------------


Notes :

- Orga TiBillet https://github.com/TiBillet
  - Fedow https://github.com/TiBillet/Fedow.git
  - Lespass https://github.com/TiBillet/Lespass.git
- Dépots personels https://github.com/joris-r?tab=repositories
  - Fedow git@github.com:joris-r/Fedow.git
  - Lespass git@github.com:joris-r/Lespass.git

```
mkdir repo
cd repo/
git clone https://github.com/TiBillet/Fedow.git
```


J'ai écrit un Dockerfile et un start_prod.sh, les deux
orienté prod avec un peu de nettoyage mais j'ai gardé
l'essentiel identique.
Le Dockerfile suppose que le context de build est ce dépot !

```
docker build -t fedow_django -f fedow/Dockerfile .
```

Et on peut faire des check avec
```
docker run --rm fedow_django poetry run python manage.py check
```

Il y a des erreurs.

Django charge settings.py qui plante immédiatement sur SECRET_KEY absente.
Il faut passer les variables d'environnement minimales — au moins SECRET_KEY, FERNET_KEY et DOMAIN.

J'écrit un `fedow/.env.example` pour documentation.

Puis d'en déduit un `.env.test`

``` sh
cat > fedow/.env.test << 'EOF'
SECRET_KEY=aaaabbbbccccddddeeeeffffgggghhhhiiiijjjjkkkk123456
FERNET_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
DOMAIN=localhost
STRIPE_TEST=1
STRIPE_KEY_TEST=sk_test_fake
TEST=1
EOF
```

La commande de test devient

``` sh
docker run --rm --env-file fedow/.env.test fedow_django \
  poetry run python manage.py check
```

Résultat OK : `System check identified no issues (0 silenced).`



## 2026-04-30 Phase 2

Docker compose est une commande de docker qui orchestre le deployement
de containeurs en vue de fournir un service (souvent une application web).

Structure (en yaml)

``` yaml
services:
  nom_du_service:
    image: nginx:1.25        # image existante depuis le Hub
    # OU
    build: .                 # construire depuis un Dockerfile local

networks:
  mon_reseau:

volumes:
  ma_donnee:
```

Il y a plusieurs sections de premier niveau possible :

- `services`
- `networks`
- `volumes`

Attention, des mots clés sont réutilisés à des niveau différents
avec des sémantiques différentes.

**Services**

**Pour** la section `services:`, on fait une sous section avec un nom de service.
Et ensuite il y a plusieurs sous sections possibles :

- `image:` ou `build`
- `networks:` (ne pas confondre avec le networks de premier niveau)
- `command:`
- `volumes:` (ne pas confondre avec le volumes de premier niveau)

**Pour** `services: > <nom-service> > image: <nom>`
cela permet de récupérer une image `<nom>` sur le hub global
(on peut aussi récupérer une image local)

**Pour** `services: > <nom-service> > build: <context>` (forme courte)
configure un répertoire `<context>` qui sert de racine pour le build


**Pour** `services: > <nom-service> > build: <context>` (forme longue)
elle permet de spécifier aussi un nom de dockerfile

Enfants :

- `context: <dir>`
- `dockerfile: <dockerfile>`


Pour `services: > <nom-service> > networks:` liste des **réseaux**

Enfants :

- `<nom-network>` Connecte `<nom-service>` sur `<nom-network>`

Remarques :

- PAR DEFAUT : un network commun à tous les services est mis en place
- les noms de services, devienent des hostname automatiquement
- les services (donc les conteneurs) peuvent utiliser que les network attaché
- sur les networks tous les ports sont ouverts entre le conteneur attaché au network
- (la directive `EXPOSE` du Dockerfile n'est que de la documentation)


**Pour** `services: > <nom-service> > ports:` liste des **ports ouverts**

gestion des ports hôtes: par défaut pas de port ouverts depuis l'hote

Enfants :

- `<ph>:<pc>` ouvre un port `<ph>` est mappé sur l'hote vers le port `<pc>` du service/conteneur


**Pour** `services: > <nom-service> > env_file: <fichier>` spécifie le fichier
contenant les variables  d'environnement


**Pour** `services: > <nom-service> > environment:` spécifie directement des
variables d'environnement. Plutot pour celle pas secretes

Enfants :

- déclaration de variables


**Pour** `services: > <nom-service> > depends_on: <service>`
attend que `<service>` soit démarré

**Pour** `services: > <nom-service> > command: <C>`
pour remplacer le `CMD` du Dockerfile par `<C>`

Deux forme :
  - en pratique `command: ["bash", "start.sh"]` offre le plus de controle
    et c'est `bash` qui recoit le SIGTERM de fermeture du container
    donc il faut mettre `exec` devant la dernière commande du script `start.sh`
  - sinon la forme string donne un environement shell (donc redirection et autre)

**Pour** `services: > <nom-service> > volumes:`

Enfants :

- `<nom>:cdir` un volume nommé pour les données persistantes
- `<hdir>:cdir` un répertoire sur le host pour un *bind mount* (transparent)



**Networks** - Réseau personalisé

Permet d'avoir plusieurs réseaux, et donc d'isoler les services entre eux.
Il faut ensuite utiliser les réseaux créé dans la section réseau des services.

Enfants :

- `<nom-réseau>` déclare un réseau



**Volumes** - Déclaration de volume nommé

Permet de déclarer des volumes, qui seront utilisé par les services.


Enfants :

- `<nom-volume>` déclare un volume



**Les commandes CLI**

Pour lancer `docker compose -f <file> up`
  (ouvre `./docker-compose.yml` par défaut)

Autres commandes

- `docker compose up` — crée et démarre les conteneurs
- `docker compose down` — arrête et supprime les conteneurs (les volumes nommés sont conservés)
- `docker compose down -v` — idem mais supprime aussi les volumes nommés
- `docker compose stop` — arrête sans supprimer les conteneurs
- `docker compose start` — redémarre des conteneurs arrêtés
- `docker compose restart` — stop + start
- `docker compose logs -f` — suit les logs
- `docker compose ps` — état des services
- `docker compose exec <service> bash` — shell dans un conteneur
- `docker compose build` — construit les images sans démarrer

Exemple plus évolué

Ici on a fait `docker compose -f fedow/docker-compose.yml up --build -d`

- `--build` reconstruction de toutes les images (mais y'a des layers en cache) 
- compose up recrée les conteneurs dont la configuration ou l'image a changé
  (on aurait pu aussi lancer des docker build à la main avant)



--------------------------------


J'ai écrit un docker-compose.yml et un .env (le même que phase précédente)
Il est un peu compliqué car on ne travail pas dans le dépot
ni dans le répertoire courant.

Lancé avec `docker compose -f fedow/docker-compose.yml up -d`

Vérifier avec `http://localhost:8000/dashboard/` (ou `curl` mais
ici c'est une page web)

On ferme avec `docker compose -f fedow/docker-compose.yml down`


## 2026-05-01 Phase 3

(complété les notes d'hier sur docker compose)

On a ajouté un volumes global et un service nginx.
Le volume est partagé par django_fedow eet django_nginx
ce qui permet à nginx d'accèder aux fichiers statiques
produit par django dans son container.

~~~ bash
docker compose -f fedow/docker-compose.yml up -d
docker compose -f fedow/docker-compose.yml ps
# Il manque fedow_nginx
docker compose -f fedow/docker-compose.yml logs fedow_nginx
# erreur car la conf nginx utilise des fichiers de log
# et ces fichier n'existe pas dans mon image
~~~

La conf utilise des fichiers normaux. La bonne pratique est
que les conteneurs écrivent leurs logs sur stdout/stderr — c'est Docker lui-même
qui gère la collecte et la rotation via son système de logging.

Je lis https://hub.docker.com/_/nginx et dans le Dockerfile officiel
Il y a

``` sh
# forward request and error logs to docker log collector
&& ln -sf /dev/stdout /var/log/nginx/access.log \
&& ln -sf /dev/stderr /var/log/nginx/error.log \
```

J'ai modifié la conf fedow/nginx/django.conf pour remettre
les chemins par défaut.

relancer le compose up. Nginx tourne, il répond sur `curl http://localhost/`


Il y avait une erreur : il faut lancer le script `fedow/start_prod.sh`

``` sh
docker compose -f fedow/docker-compose.yml up --build -d
```

Avec `curl http://localhost/static/` On a une erreur 403 Forbidden.
Mais c'est normal puisque le listing des dossiers est interdit.

Cherchons un truc `docker exec fedow-fedow_django-1 ls /home/fedow/Fedow/www/static/`
On le récupère avec `curl -v http://localhost/static/css/main.css`
En fait il est vide mais peut importe (on peut le voir en ajoutant `-v`)


## 2026-05-02 Samedi midi.

J'ai une interrogation sur les bonnes pratiques pour les mise à jour
suite à des failles critiques dans des bibliotheques de base.
Toutes les images contiennent des version différentes des bibliotheques.
Potentiellement, il faut tout mettre à jour régulièrement.


Pour mettre les images

- les images directement utilisées dans le le docker-compose.yml
  - c'est màj par `docker compose pull`
- les images de base des Dockerfiles
  - c'est màj par `docker compose build --pull`


Si on utilise un docker-compose, il suffit de faire ça pour màj tout

``` sh
docker compose pull && docker compose build --pull && docker compose up -d
```


Dans mon cas précis en ce moment c'est 

``` sh
docker compose -f fedow/docker-compose.yml pull && \
  docker compose -f fedow/docker-compose.yml build --pull && \
  docker compose -f fedow/docker-compose.yml up -d
```

Et il faudra le faire régulièrement




## 2026-05-03 Dimanche 

**Phase 4**

Je récupère la branche V2 du dépot git officiel

``` sh
cd repo/
git clone https://github.com/TiBillet/Lespass.git
```

J'ai écrit un `Dockerfile` pour Lespass.
Même principe que Fedow.

J'ai utilisé une variable docker pour le chemin spécifique à ce travail.
C'est `ARG LESPASS_SRC=./repo/Lespass` à l'utilisation `${LESPASS_SRC}`

On a été obligé de faire `RUN mkdir -p logs` à cause des setting de Django
qui écrivent dans ce répertoire les logs. Django a sa propre config de
logging dans settings.py qui écrit dans ce dossier, indépendamment des
logs de Gunicorn (qui était configuré en arg CLI).

Pour trouver le répertoire principale d'un app Django peut avoir des noms
divers, ici c'est `TiBillet`. Il contient un `settings.py` et les conf pour
les serveur http `wsgi.py`.

On a écrit `lespass/start_prod.sh` avec beaucoup moins de choses que
dans l'original.

Pour construire l'image docker (sans docker compose)
``` sh
docker build -f lespass/Dockerfile -t lespass-test .
```

Ensuite on découvre ce qu'il manque (les variables d'ENV en particulier)
en essayant le check de Django

``` sh
docker run --rm -e DOMAIN=test.local -e SUB=test -e META=test -e DJANGO_SECRET=changeme-50-chars-xxxxxxx
xxxxxxxxxxxxxxxxxxxxxxxxx lespass-test poetry run python manage.py check
```


**Phase 5** Début docker-compose Lespass

J'écrit un `docker-compose.yml` pour lespass avec son postgres.
On utilise `depends_on` pour exprimer la dépendance obligatoire.

Pour le lancer `docker compose -f lespass/docker-compose.yml up`

Gestion du `POSTGRES_HOST` dans le compose plutot que dans fichier `.env`
car le hostname de postgres est défini par le compose.
Les variables dans `environment:` écrasent celle du fichier.


État des container `docker compose -f lespass/docker-compose.yml ps`

test avec `curl -v http://localhost:8002/`


**Phase 6** Add Redis and Celery to Lespass

TODO : il manque des `restart: unless-stopped`, par défaut c'est `no`.

Pour Redis, il suffit d'utiliser l'image officielle.

Pour Celery, c'est un package python qui est présent dans l'image de lespass.
Donc on réutilise l'image, mais on a une commande spécifique.


**Phase 7** - Add Memcached and Nginx to Lespass

Pour chercher dans les fichier

grep -rn "MEMCACHE" repo/Lespass/ --include="*.py"


Dans un fichier

grep -n "CACHE\|memcach" repo/Lespass/TiBillet/settings.py


Dans docker compose, pour un service
`links: <A>:<B>` permet de créer un alias réseau `<B>`


Ajouter memcached, c'est facile mais il faut utiliser un `link` car
l'image lespass suppose qu'il est accessible au hostname `memcached`.
Il faut aussi ajouter des `depend_on`.


Pour nginx (Engine X), une image du hub.
On enleve l'exposition du port de django (plus utile).
Ajouter une volume nommé pour les fichiers statiques.
Pas oublier le depend_on vers django. 

`docker compose -f lespass/docker-compose.yml up -d`

Il y a un problème de permission sur `/DjangoFiles/www` car
le volume qu'on vient d'ajouter à les droit root.
La solution est de créer en avance les chemins dans le script
de lancement pour que les répertoires existent avec le bon propriétaire.
Ca ne peut pas être dans le Dockerfile car les volumes sont appliquées
par dessus les images.
==> mais cela n'a pas fonctionné, donc on a utilisé un bind mount
avec un répertoire sur le host. Il y a aussi eu un problème car
docker a tout créé en root, mais sur le host on peut corriger à
la main le proprio.

`docker compose -f lespass/docker-compose.yml logs lespass_django`

Pour voir des logs
`docker compose -f lespass/docker-compose.yml logs lespass_django`


Pour relancer avec un rebuild
`docker compose -f lespass/docker-compose.yml up --build`


On vérifie que ca marche avec `curl http://localhost/`
Et regarder les logs.
docker compose -f lespass/docker-compose.yml logs lespass_django --since=2m

Ca ne marchait toujours pas car docker avait créé les fichiers avec root.
J'ai chown sur mon host.

Avec `curl -v http://localhost/`. On a une erreur 404, donc c'est bon.

Note : gestion des volumes par Docker, c'est en root. Ce n'est pas satisfaisant.



**Phase 8** - Wire Lespass and Fedow together

On a maintenant des docker compose pour Lespass et Fedow.
Ils sont sur les deux réseau par défaut et ne peuvent donc
pas de joindre directement.

On se propose l'approche de faire un réseau "externe"
c'est à dire pas géré par docker compose up/down.
Comme les réseaux internes, il n'est pas accessible par
l'hote (sauf via ports exposés).
Mais on peut l'utiliser dans chaque docker compose.
`docker network create tibillet_backend`

Dans chaque docker compose
``` yaml
networks:
  tibillet_backend:
    external: true
```

Puis pour un service
``` yaml
services:
  lespass_django:
    networks:
      - tibillet_backend
```

Il y a un problème pour lancer les deux ensemble : conflit
sur le port 80. J'ai enlevé temporairement celui de lespass.

``` sh
docker compose -f lespass/docker-compose.yml up -d
docker compose -f fedow/docker-compose.yml up -d
docker network inspect tibillet_backend |grep Name
```

On voit
``` json
        "Name": "tibillet_backend",
                "Name": "lespass-lespass_django-1",
                "Name": "fedow-fedow_django-1",
```

Un autre problème : le réseau par défaut (nommé `default`) n'est plus appliqué
sur les services. On peut le déclarer dans le networks global pour retrouver cela.
De plus pour les services avec une clause networks, il faut l'ajouter aussi.

Testons la com
`docker exec -it lespass-lespass_django-1 curl http://fedow-fedow_django-1:8000/`

On a une erreur 400. Mais donc la connexion réseau fonctionne.




**Phase 9** - Compose unique pour Coolify

Je fusionne les deux docker compose.

Enlever les déclaration de réseau. Supprimer le réseau externe
`docker network rm tibillet_backend `

Ajouter les volumes : `lespass_db` et `fedow_db`. Les utiliser.
Supprimer le volume `fedow_static`.

Supprimer les deux ports 80.

On garde les deux fichier .env séparé.

Ca ne marche pas du premier coup, car la bdd n'est pas prete pour
la connexion lorsque lespass veux se connecter.

En relancant, c'est ok.

Il n'y a plus de port exposé, donc on test de l'intérieur
`docker exec deploy-lespass_django-1 curl http://lespass_nginx/`

On récupère un 404, donc ca tourne.


**Phase 10** - Deploy on Coolify

On a du ajouter les deux dépot git en submodule pour que Coolify
les clone aussi.

Les variables d'env qui ont le même nom sont un problème pur coolify
car il ne sert pas du tout des fichier d'env. Qui ne sont pas dans le
git de toute façon...
Donc on a ajoutré dans fedow/start_prod.sh des 
export DOMAIN=$FEDOW_DOMAIN pour dédupliquer les variables.

Ainsi j'ai pu saisir les variable dans l'interface de Coolify.

Enuite, on a eu le même problème qu'en local avec le répertoire BIND
pour les fichier statiques qui étaient en root.
Normalement Coolify supprime le répertoire de build mais il garde
quand même les répertoires bindé. J'ai donc pu corriger le propriétaire.

Enuite, les fichiers de conf de nginx était absent de ses répertoires.
Rajouté à la main (mais ca ne survirera pas à un redeploy)


cat > /data/coolify/applications/ghlvam6iuanigrg1zl9ilrlz/lespass/nginx/django.conf << 'EOF'
server {

    listen 80;
    server_name localhost;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    location /static {
        root /www;
    }

    location /media {
        root /www;
    }

    location / {
        # everything is passed to Gunicorn
        proxy_pass http://lespass_django:8002;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $host;
        proxy_redirect off;
    }
}
EOF

cat > /data/coolify/applications/ghlvam6iuanigrg1zl9ilrlz/fedow/nginx/django.conf << 'EOF'
server {

    listen 80;
    server_name localhost;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    location /static {
        root /www;
    }

    location /media {
        root /www;
    }

    location / {
        # everything is passed to Gunicorn
        proxy_pass http://fedow_django:8000;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $host;
        proxy_redirect off;
    }
}
EOF

Il y a un problème pour avoir les certificats Let's Encrypt.
Traefik ne peut pas résoudre acme-v02.api.letsencrypt.org
depuis ses containers — problème DNS interne Docker.

Certificat autosigné Traefik utilisé pour l'instant.
les services répondent en HTTPS avec -k

Résultat : Lespass et Fedow tournent sur
https://lespass.tibillet.intra.lafab.org et https://fedow.tibillet.intra.lafab.org.

## 2026-05-04 - Travail sur les volumes de TiBillet

### Répertoires prévus par les dépôts TiBillet

Les deux dépôts prévoient des répertoires spécifiques
pour les données persistantes, signalés par la présence
d'un fichier `__init__` vide qui force git à les traquer.

**Fedow**

- `www/` — fichiers statiques générés par `collectstatic`
- `logs/` — logs applicatifs Django
- `database/` — base SQLite (`db.sqlite3`)
- `backup/` — sauvegardes manuelles (contient `dumps/`
  et un script `save.sh`)

**Lespass**

- `www/` — fichiers statiques générés par `collectstatic`
- `logs/` — logs applicatifs Django
- `Backup/` — sauvegardes (contient un sous-dossier
  `logs/`)

Note : Lespass utilise Postgres, pas SQLite — donc pas de
répertoire `database/`. La base de données est gérée par
le container `lespass_postgres`.

**Volumes de bases de données (gérés par les images
officielles)**

- `fedow_db` — monté dans `fedow_django` à
  `/home/fedow/Fedow/database` (SQLite)
- `lespass_db` — monté dans `lespass_postgres` à
  `/var/lib/postgresql/data` (Postgres)

Ces volumes sont initialisés correctement par leurs images
respectives. Pas d'intervention nécessaire de notre côté.

### Problème avec le .dockerignore

Notre `.dockerignore` exclut `repo/*/www/` et
`repo/*/logs/`. Ces répertoires ne sont donc pas copiés
dans les images par le `COPY --chown=...`. Quand Docker
monte un volume à ces chemins, il crée les répertoires
lui-même — en `root:root`.

Résultat : le process applicatif (qui tourne en tant que
`tibillet` ou `fedow`) ne peut pas écrire dans ces
répertoires.

Pour `logs`, on a contourné le problème dans les
Dockerfiles avec `RUN mkdir -p logs` (qui tourne en tant
que l'utilisateur applicatif). Mais `www` n'a jamais eu
ce traitement.

La solution retenue : **retirer `repo/*/www/` et
`repo/*/logs/` du `.dockerignore`**, pour que le `COPY
--chown=tibillet:tibillet` les copie dans l'image avec la
bonne ownership. C'est cohérent avec ce que les dépôts
prévoient.

### Résolution des problèmes de volumes (ISSUES §2 et §3)

**Problème `.dockerignore`**

On a découvert que `www/` et `logs/` étaient exclus du
`.dockerignore`, ce qui empêchait leur copie dans les
images. Docker les créait donc en `root:root` au montage,
rendant ces répertoires inaccessibles en écriture pour les
utilisateurs applicatifs (`fedow`, `tibillet`).

Solution : retirer `repo/*/www/` et `repo/*/logs/` du
`.dockerignore`. Ces répertoires sont copiés avec
`--chown=fedow:fedow` et `--chown=tibillet:tibillet` et
ont donc la bonne ownership dans les images.

**Variables d'environnement Fedow**

Le `.env` de Fedow n'avait pas été mis à jour avec les
noms préfixés `FEDOW_*` introduits dans `start_prod.sh`.
Mis à jour et `.env.example` également corrigé.

**Volumes nommés**

Ajout de tous les volumes nommés dans le compose :

- `fedow_db` — base SQLite de Fedow
- `fedow_static` — fichiers statiques, partagé entre
  `fedow_django` et `fedow_nginx`
- `fedow_logs` — logs de Fedow
- `fedow_backup` — sauvegardes de Fedow
- `lespass_db` — base Postgres de Lespass
- `lespass_static` — fichiers statiques, partagé entre
  `lespass_django` et `lespass_nginx`
- `lespass_logs` — logs de Lespass
- `lespass_backup` — sauvegardes de Lespass

Le volume statique partagé remplace le bind mount
`./lespass/www` qui causait des problèmes de permissions.

**Confs Nginx dans les images (ISSUE §3)**

Créé un `Dockerfile` dans `fedow/nginx/` et `lespass/nginx/`
qui embarque la conf avec `COPY django.conf`. Les bind
mounts de conf sont supprimés du compose. La conf Nginx
survit maintenant aux redéploiements.

**Commandes utiles**

``` sh
# Nettoyage complet
docker compose down -v
docker volume prune -a

# Rebuild et relance
docker compose down -v && docker compose up --build -d

# Vérifier l'état
docker compose ps
docker compose logs fedow_django --tail=30

# Vérifier les fichiers statiques dans Nginx
docker exec deploy-fedow_nginx-1 ls /www/static
docker exec deploy-lespass_nginx-1 ls /www/static
```


### Architecture multi-tenant de Lespass

Lespass est obligatoirement multi-tenant, basé sur
`django-tenants`. Chaque tenant a son propre schéma
PostgreSQL. Il n'existe pas de mode "monotenant" — même
une installation minimale crée plusieurs tenants.

**Les 4 tenants créés par `manage.py install` :**

- **PUBLIC** (ROOT) — le tenant racine, accessible sur
  `{DOMAIN}` et `www.{DOMAIN}`. Son nom est défini par
  la variable `PUBLIC`.
- **META** — l'agenda fédéré, accessible sur
  `{META}.{DOMAIN}` (ex: `agenda.tibillet.localhost`).
- **FIRST_SUB** — le premier lieu/place, accessible sur
  `{SUB}.{DOMAIN}` (ex: `lespass.tibillet.localhost`).
- **FEDERATION_FED** — porte la monnaie FED, pas d'accès
  HTTP, usage interne uniquement.

La commande `install` est idempotente : elle vérifie si
les tenants existent avant de les créer.

**Fichiers clés dans le repo Lespass :**

- `Administration/management/commands/install.py`
- `Customers/models.py` — modèle Client avec les
  catégories ROOT, META, SALLE_SPECTACLE, FED
- `TiBillet/settings.py` — SHARED_APPS vs TENANT_APPS

### Lespass requiert Fedow en HTTPS pour l'initialisation

La commande `install` commence par appeler
`https://{FEDOW_DOMAIN}/helloworld/` pour vérifier que
Fedow est accessible. Elle échoue si :

- `FEDOW_DOMAIN` ne résout pas depuis l'intérieur du
  container (ex: `localhost` = le container lui-même,
  pas le host)
- Fedow n'est pas accessible en HTTPS (pas de TLS)

Cela confirme que Fedow doit avoir un domaine public avec
un certificat TLS valide pour que l'installation puisse
se faire. En local, c'est un blocage.

**Piste :** utiliser `verify=False` dans la requête (hack
de dev) ou monter un certificat autosigné sur Fedow en
local. Mais ce n'est pas résolu.

### Variables d'environnement : conflit FEDOW_DOMAIN

`FEDOW_DOMAIN` désigne deux choses différentes selon le
contexte :

- Dans **Lespass** `.env` : l'URL de Fedow à appeler
- Dans notre **`fedow/start_prod.sh`** : on a fait
  `export DOMAIN=$FEDOW_DOMAIN`, donc c'est le propre
  domaine de Fedow

C'est le même nom, deux significations. C'est noté dans
le §4 de ISSUES.md.

### Environnement de dev fourni par Jonas (développeur principal)

Jonas a fourni un fichier `env-joris` et une procédure
de mise en place d'un environnement de dev. Points clés :

**`flush.sh` est la commande d'initialisation en dev**

Ce script fait tout : drop/create de la base, migrations,
`manage.py install`, fixtures de démo, puis lance le
serveur de dev. Il ne fonctionne que si `DEBUG=1`.

Il est plus complet que `manage.py install` seul — il
ajoute des données de démo (`demo_data_v2`) utiles pour
tester. Pour une mise en production, on n'en voudra pas.

**`TEST=1` et `DEBUG=1` débloquent le dev local**

Ces flags modifient le comportement de Lespass en dev :
ils byppassent probablement la vérification SSL lors de
l'appel à Fedow. C'est pour ça que `manage.py install`
échouait dans notre `.env.test` — on avait `TEST=0`.

**Le setup dev est différent de notre deploy**

- Utilise le `docker-compose.yml` officiel du repo
  Lespass (`repo/Lespass/docker-compose.yml`)
- Nécessite un réseau externe `frontend` (`docker network
  create frontend`)
- Fedow et Lespass sont accessibles via des sous-domaines
  `.localhost` (`fedow.tibillet.localhost`,
  `lespass.tibillet.localhost`) grâce à Firefox qui
  résout `*.localhost` vers `127.0.0.1`
- `FEDOW_DOMAIN='fedow.tibillet.localhost'` dans le
  `.env` de Lespass

**Stripe test et email**

Jonas a fourni des credentials Stripe test et SMTP
valides pour le dev. Ces credentials sont dans `env-joris`
qui n'est pas commité.


## 2026-05-04 Issue 7. Let's Encrypt ne fonctionne pas

**Diagnostic**

Le container `coolify-proxy` (Traefik) ne pouvait pas résoudre
`acme-v02.api.letsencrypt.org`. L'erreur dans les logs :

```
Unable to obtain ACME certificate for domains
error="...lookup acme-v02.api.letsencrypt.org on
127.0.0.11:53: server misbehaving"
```

**Cause racine**

Le serveur Coolify est une machine physique derrière une
Freebox. Le DNS configuré sur l'hôte est `192.168.1.254`
(la Freebox agit comme proxy DNS local). Les containers
Docker sont sur des réseaux `10.x.x.x` — la Freebox refuse
les requêtes DNS venant de ces IPs non reconnues comme
locales. Résultat : SERVFAIL pour tout nom externe.

**Fix appliqué**

Ajout de DNS publics dans `/etc/docker/daemon.json` :

```json
"dns": ["1.1.1.1", "8.8.8.8"]
```

Suivi de `sudo systemctl restart docker`. Après redémarrage,
`nslookup` depuis le container fonctionne et le certificat
pour `site.intra.lafab.org` a été émis automatiquement.

**Leçons**

- Les logs Traefik sont dans `docker logs coolify-proxy`
- La Freebox est un proxy DNS local, pas accessible depuis
  les réseaux Docker
- Wildcard DNS A record `*.intra.lafab.org` : OK pour router
  le trafic vers le serveur
- Wildcard certificat TLS `*.intra.lafab.org` : impossible
  sans DNS-01, et o2switch (cPanel) n'a pas d'API ACME
  compatible — chaque service TiBillet aura son propre
  sous-domaine avec un cert individuel via HTTP-01


## 2026-05-04 Premier déploiement fonctionnel sur Coolify

### Préparation du compose

Avant de redéployer, plusieurs corrections au
`docker-compose.yml` :

- `env_file:` conservé + `environment:` avec valeurs vides
  ajouté pour que Coolify détecte et pré-remplisse les
  variables dans son interface (issue §10)
- `manage.py install` ajouté dans `lespass/start_prod.sh`
  avec `|| echo WARNING` pour ne pas bloquer gunicorn
- Healthcheck `pg_isready` sur `lespass_postgres` et
  `condition: service_healthy` dans les `depends_on`
  (issue §11)
- `SUB=lafabrique` — le tenant de La Fabrique s'appelle
  `lafabrique`, accessible sur `lafabrique.intra.lafab.org`
- Variables Stripe ajoutées pour Lespass et Fedow (préfixe
  `FEDOW_*` pour Fedow via `start_prod.sh`)
- `CELERY_BROKER` et `CELERY_BACKEND` ajoutés à
  `lespass_django` et `lespass_celery`
- `FERNET_KEY` partagé entre Fedow et Lespass (non préfixé)

### Problèmes rencontrés au déploiement

**Stripe obligatoire pour `manage.py install`**

`install.py` lève une exception si aucune clé Stripe
n'est présente et que `DEBUG=False`. Les credentials
sont à remplacer par ceux de La Fabrique avant prod.

**`manage.py install` partiel : FIRST_SUB non créé**

Au premier run réussi (après ajout des clés Stripe),
`install` a créé PUBLIC, META et federation_fed mais
pas le tenant FIRST_SUB. Raison : `Domain.objects.create()`
(pas `get_or_create`) échoue si le domain existe déjà
d'un run partiel précédent. Les runs suivants retournent
trop tôt (`return` ligne 41 si PUBLIC existe).

Solution : créer le tenant manuellement via Django shell :

```python
from Customers.models import Client, Domain
tenant, _ = Client.objects.get_or_create(
    schema_name='lafabrique',
    defaults={'name': 'lafabrique', 'on_trial': False,
              'categorie': Client.SALLE_SPECTACLE})
Domain.objects.get_or_create(
    domain='lafabrique.intra.lafab.org',
    defaults={'tenant': tenant, 'is_primary': True})
```

**Fedow handshake et admin manquants**

Puisque FIRST_SUB a été créé manuellement (bypass
d'install), deux étapes ont dû être rejouées via shell :

1. `rootConfig.root_fedow_handshake(fedow_domain)` dans
   le contexte du tenant `public` — crée la clé API
   chiffrée (`fedow_create_place_apikey`) dans
   `RootConfiguration`
2. Création du user admin + `FedowAPI()` dans le contexte
   du tenant `lafabrique` — crée le "lieu" dans Fedow et
   lie le wallet

**`CELERY_BACKEND` pointait vers `redis://redis:6379/0`**

Le hostname `redis` n'existe pas dans notre réseau Docker.
Il fallait `redis://lespass_redis:6379/0`. Variable
`CELERY_BACKEND` ajoutée au compose.

### Résultat

- https://lafabrique.intra.lafab.org répond en HTTPS
- Connexion par email fonctionne (Celery + Redis OK)
- Compte admin prévu opérationnel
- Fedow lié à Lespass, wallet créé