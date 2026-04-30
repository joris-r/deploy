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

Pour configurer un service:

- `image` image existante local ou hub global
- ou alors `build <context>` on va utiliser un Dockerfile dans ce context
- forme longue de `build:`
  - `context: <dir>`
  - `dockerfile: <dockerfile>`
- `ports <host>:<container>` ouvrir le port `<host>` qui est branché sur `<container>`.
- `env_file` le fichier des variables d'environnement
- sinon directement dans `environment` (plutot celle pas secretes)
- `depends_on <service>` attend que `<service>` soit démarré
- `command <C>` pour remplacer le `CMD` du Dockerfile
  - en pratique `command: ["bash", "start.sh"]` offre le plus de controle
    et c'est `bash` qui recoit le SIGTERM de fermeture du container
    donc il faut mettre `exec` devant la dernière commande du script `start.sh`
  - sinon la forme string donne un environement shell (donc redirection et autre)
- `volumes <A>:<cdir>`, `<cdir>` est dans le container, `<A>` peut être
  -  `<nom>` un volume nommé pour les données persistantes
  -  `<hdir>` un répertoire sur le host pour un *bind mount* (transparent)
- `networks` liste des réseaux connecté
  - PAR DEFAUT : un network commun à tous les services est mis en place

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

--------------------------------


J'ai écrit un docker-compose.yml et un .env (le même que phase précédente)
Il est un peu compliqué car on ne travail pas dans le dépot
ni dans le répertoire courant.

Lancé avec `docker compose -f fedow/docker-compose.yml up -d`

Vérifier avec `http://localhost:8000/dashboard/` (ou `curl` mais
ici c'est une page web)

On ferme avec `docker compose -f fedow/docker-compose.yml down`