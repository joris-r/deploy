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

---------------------------------------------------------


Notes :

- Orga TiBillet https://github.com/TiBillet
  - Fedow https://github.com/TiBillet/Fedow.git
  - Lespass https://github.com/TiBillet/Lespass.git
- Dépots personels https://github.com/joris-r?tab=repositories
  - Fedow git@github.com:joris-r/Fedow.git
  - Lespass git@github.com:joris-r/Lespass.git

~~~
mkdir repo
cd repo/
git clone https://github.com/TiBillet/Fedow.git
~~~


J'ai écrit un Dockerfile et un start_prod.sh, les deux
orienté prod avec un peu de nettoyage mais j'ai gardé
l'essentiel identique.
Le Dockerfile suppose que le context de build est ce dépot !

~~~
docker build -t fedow_django -f fedow/Dockerfile .
~~~

Et on peut faire des check avec
~~~
docker run --rm fedow_django poetry run python manage.py check
~~~

Il y a des erreurs.

Django charge settings.py qui plante immédiatement sur SECRET_KEY absente.
Il faut passer les variables d'environnement minimales — au moins SECRET_KEY, FERNET_KEY et DOMAIN.

J'écrit un `fedow/.env.example` pour documentation.

Puis d'en déduit un `.env.test`

~~~
cat > fedow/.env.test << 'EOF'
SECRET_KEY=aaaabbbbccccddddeeeeffffgggghhhhiiiijjjjkkkk123456
FERNET_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
DOMAIN=localhost
STRIPE_TEST=1
STRIPE_KEY_TEST=sk_test_fake
TEST=1
EOF
~~~

La commande de test devient

~~~
docker run --rm --env-file fedow/.env.test fedow_django \
  poetry run python manage.py check
~~~

Résultat OK : `System check identified no issues (0 silenced).`


