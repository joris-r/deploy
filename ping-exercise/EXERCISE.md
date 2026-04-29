# Docker networking --- hands-on exercise

## Memo

### Useful commands

| What you want                            | Command                                 |
| ---------------------------------------- | --------------------------------------- |
| Start all services in background         | `docker compose up -d`                  |
| Stop and remove containers               | `docker compose down`                   |
| List running containers                  | `docker ps`                             |
| Run a command inside a running container | `docker exec <container> <command>`     |
| Ping another host (4 packets)            | `ping <host> -c 4`                      |
| List networks Docker knows about         | `docker network ls`                     |
| Inspect a network (who's connected)      | `docker network inspect <network_name>` |

Et les réseau d'un container :
`docker inspect <container> --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'`

Autres commandes utiles

- pour voir les conteneurs qui tournent `docker ps`
- avoir juste la liste des IDs `docker ps -q`
- donc *tout* stopper : `docker stop $(docker ps -q)`
- ensuite `docker system prune` supprime les conteneurs qui ne tournent pas
  et les image *dangling* (sans tag et inutilisé)

Connaire les ressources utilisées
~~~
docker system df
~~~

/!\ **Tout** arreter et supprimer /!\
**Même les volumes nommés !**
**Sans confirmation !**
~~~
docker stop $(docker ps -q) 2>/dev/null; docker volume prune -a -f; docker system prune -a -f --volumes
~~~



### Key concept

Containers on the **same network** can reach each other by **service name**.
Containers on **different networks** are isolated --- they cannot reach each
other even if both are running.

Docker creates a network named `<project_folder>_<network_name>` automatically
when you use `docker compose`.

--------------------------------------------------------------------------------

## Exercises

### 1 --- Start the playground

Bring up the two containers defined in `docker-compose.yml`. Verify they are
running.

> Expected: two containers listed, status `Up`.

docker compose up -d
Ca récupère Alpine, y'a effectivement le network ping-exercise_playground
et j'ai deux container

docker ps
"sleep infinity" est un "serveur null"

docker network ls
j'ai pas mal de bazar de précédente conf

--------------------------------------------------------------------------------

### 2 --- Confirm the network exists

Find the network Docker created for this compose project.

> Expected: a network whose name contains `playground`.


$ docker network ls |grep -E "ping|NETWORK ID"
NETWORK ID     NAME                        DRIVER    SCOPE
68ecfdda4d3f   ping-exercise_playground    bridge    local

--------------------------------------------------------------------------------

### 3 --- Check who is on the network

Inspect that network to see which containers are attached to it.

> Expected: both `alice` and `bob` appear in the output.

docker network  inspect ping-exercise_playground
==> C'est un horrible json

$ docker network  inspect ping-exercise_playground | grep -E "Name|IPv4"
        "Name": "ping-exercise_playground",
        "EnableIPv4": true,
                "Name": "alice",
                "IPv4Address": "172.19.0.3/16",
                "Name": "bob",
                "IPv4Address": "172.19.0.2/16",

$docker network inspect ping-exercise_playground --format '{{range .Containers}}{{.Name}} {{end}}'
alice bob

**About the format syntax**
It's Go templates — Docker uses Go under the hood and exposes the same templating system.

{{range .Containers}} — iterate over the Containers field (it's a map)
{{.Name}} — for each item in the loop, print its Name field
{{end}} — close the loop
The . always means "current object". Outside the loop . is the whole network object, inside the loop . is one container entry.

You can nest fields too — {{.IPAM.Config}} would dig into IPAM → Config.


==> Donc on a A et B

--------------------------------------------------------------------------------

### 4 --- Ping across containers

From inside `alice`, send 4 pings to `bob` using its service name. Then do the
reverse.

> Expected: 0% packet loss in both directions.


$ docker exec alice ping bob -c 2
PING bob (172.19.0.2): 56 data bytes
64 bytes from 172.19.0.2: seq=0 ttl=64 time=0.072 ms
64 bytes from 172.19.0.2: seq=1 ttl=64 time=0.082 ms

--- bob ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.072/0.077/0.082 ms



$ docker exec bob ping alice -c 6 |grep packets
6 packets transmitted, 6 packets received, 0% packet loss

--------------------------------------------------------------------------------

### 5 --- Break the network

Edit `docker-compose.yml`: remove the `networks:` key from `bob` only (keep it
on `alice` and keep the top-level `networks:` block). Restart the stack, then
try to ping `bob` from `alice` again.

> Expected: ping fails. Why?

OK j'ai enlevé de B seulement

docker compose down 
docker compose up
docker exec bob ping alice -c 4 |grep packets

$ docker exec bob ping alice -c 4 |grep packets
ping: bad address 'alice'


$ docker network  inspect ping-exercise_playground | grep -E "Name|IP
v4"
        "Name": "ping-exercise_playground",
        "EnableIPv4": true,
                "Name": "alice",
                "IPv4Address": "172.19.0.2/16",

==> A et B n'ont plus de réseau en commun

--------------------------------------------------------------------------------

### 6 --- Isolation between networks

Add a third service `charlie` on a **new** network called `isolated`. Restart
the stack. Try to ping `charlie` from `alice`.

> Expected: ping fails. Try to explain in one sentence why, even though charlie
> is running.


J'ai ajouté un sercie charlie similaire aux autre mais avec le networks `isolated`

~~~
docker compose down
docker compose up
docker exec alice ping charlie
~~~

> `ping: bad address 'charlie'`

Le container Alice n'est pas du tout sur le network isolated, donc il ne
peut pas joindre charlie

--------------------------------------------------------------------------------

### Cleanup

Stop and remove everything when you are done.

`docker compose down` dans le répertoire avec le docker compose

