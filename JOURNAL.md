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


**Phase 6**

