# Docker CLI Reference

Reference: [Docker CLI Documentation](https://docs.docker.com/reference/cli/docker/)

## 1. Container Management

Commands for creating, running, inspecting, and managing containers.

| Command | Description |
| --- | --- |
| `docker container create` | Create a container |
| `docker container run` | Create and run a container |
| `docker container start` | Start stopped containers |
| `docker container stop` | Stop running containers |
| `docker container restart` | Restart containers |
| `docker container kill` | Force-stop containers |
| `docker container pause` | Pause container processes |
| `docker container unpause` | Resume paused containers |
| `docker container ls` | List containers |
| `docker container inspect` | Inspect container details |
| `docker container logs` | View container logs |
| `docker container exec` | Execute a command inside a running container |
| `docker container attach` | Attach to a running container |
| `docker container cp` | Copy files between host and container |
| `docker container rename` | Rename a container |
| `docker container update` | Update container resource settings |
| `docker container rm` | Remove containers |
| `docker container prune` | Remove stopped containers |
| `docker top` | Display processes running in a container |
| `docker stats` | Display resource usage statistics |
| `docker wait` | Wait for a container to stop |

## 2. Image Management

Commands for building, downloading, inspecting, and distributing images.

| Command | Description |
| --- | --- |
| `docker image build` | Build an image |
| `docker image ls` | List images |
| `docker image pull` | Download an image |
| `docker image push` | Upload an image |
| `docker image tag` | Tag an image |
| `docker image inspect` | Inspect image details |
| `docker image history` | Show image layers and history |
| `docker image save` | Save images to an archive |
| `docker image load` | Load images from an archive |
| `docker image import` | Create an image from a filesystem archive |
| `docker image export` | Export a container filesystem |
| `docker image rm` | Remove images |
| `docker image prune` | Remove unused images |
| `docker commit` | Create an image from a container |
| `docker search` | Search Docker Hub for images |
| `docker manifest` | Manage image manifests and manifest lists |
| `docker buildx` | Use advanced image build capabilities |

## 3. Docker Compose

Commands for defining and managing multi-container applications.

| Command | Description |
| --- | --- |
| `docker compose up` | Create and start services |
| `docker compose down` | Stop and remove application resources |
| `docker compose start` | Start existing services |
| `docker compose stop` | Stop services |
| `docker compose restart` | Restart services |
| `docker compose ps` | List project containers |
| `docker compose logs` | View service logs |
| `docker compose exec` | Execute a command in a service container |
| `docker compose run` | Run a one-off command |
| `docker compose build` | Build service images |
| `docker compose pull` | Pull service images |
| `docker compose push` | Push service images |
| `docker compose config` | Validate and render Compose configuration |
| `docker compose images` | List images used by services |
| `docker compose events` | Receive container events |
| `docker compose top` | Display service processes |
| `docker compose pause` | Pause services |
| `docker compose unpause` | Resume services |
| `docker compose rm` | Remove stopped service containers |
| `docker compose watch` | Watch files and synchronize or rebuild services |

## 4. Network Management

Commands for creating and managing container networks.

| Command | Description |
| --- | --- |
| `docker network ls` | List networks |
| `docker network create` | Create a network |
| `docker network inspect` | Inspect network configuration |
| `docker network connect` | Connect a container to a network |
| `docker network disconnect` | Disconnect a container from a network |
| `docker network rm` | Remove networks |
| `docker network prune` | Remove unused networks |

## 5. Volume and Storage Management

Commands for managing persistent container data.

| Command | Description |
| --- | --- |
| `docker volume ls` | List volumes |
| `docker volume create` | Create a volume |
| `docker volume inspect` | Inspect volume details |
| `docker volume rm` | Remove volumes |
| `docker volume prune` | Remove unused volumes |

## 6. Registry and Authentication

Commands for authenticating with registries and exchanging images.

| Command | Description |
| --- | --- |
| `docker login` | Authenticate to a registry |
| `docker logout` | Log out from a registry |
| `docker pull` | Download an image |
| `docker push` | Upload an image |
| `docker search` | Search Docker Hub |

## 7. Docker Swarm and Orchestration

Commands for managing a Docker Swarm cluster.

| Command | Description |
| --- | --- |
| `docker swarm init` | Initialize a Swarm |
| `docker swarm join` | Join a Swarm |
| `docker swarm join-token` | Display a join token |
| `docker swarm leave` | Leave a Swarm |
| `docker swarm update` | Update Swarm settings |
| `docker node ls` | List Swarm nodes |
| `docker node inspect` | Inspect a node |
| `docker node promote` | Promote a node to manager |
| `docker node demote` | Demote a manager node |
| `docker node update` | Update node settings |
| `docker node rm` | Remove a node |
| `docker service create` | Create a service |
| `docker service ls` | List services |
| `docker service ps` | List service tasks |
| `docker service inspect` | Inspect a service |
| `docker service logs` | View service logs |
| `docker service scale` | Scale service replicas |
| `docker service update` | Update a service |
| `docker service rollback` | Roll back a service |
| `docker service rm` | Remove a service |
| `docker stack deploy` | Deploy a stack |
| `docker stack ls` | List stacks |
| `docker stack ps` | List stack tasks |
| `docker stack services` | List stack services |
| `docker stack rm` | Remove a stack |

## 8. Build System

Commands for managing Docker builds and build environments.

| Command | Description |
| --- | --- |
| `docker builder build` | Build an image |
| `docker builder prune` | Remove build cache |
| `docker buildx build` | Build using Buildx |
| `docker buildx bake` | Build from a Bake definition |
| `docker buildx ls` | List builders |
| `docker buildx create` | Create a builder |
| `docker buildx inspect` | Inspect a builder |
| `docker buildx use` | Select a builder |
| `docker buildx stop` | Stop a builder |
| `docker buildx rm` | Remove a builder |
| `docker buildx prune` | Remove Buildx cache |
| `docker buildx version` | Show Buildx version |

## 9. System Administration and Cleanup

Commands for monitoring Docker and removing unused resources.

| Command | Description |
| --- | --- |
| `docker system df` | Show disk usage |
| `docker system events` | Monitor Docker events |
| `docker system info` | Display system information |
| `docker system prune` | Remove unused Docker resources |
| `docker info` | Display Docker daemon information |
| `docker version` | Show client and server versions |
| `docker inspect` | Inspect Docker objects |
| `docker events` | Stream Docker events |

## 10. Context and Remote Daemons

Commands for selecting and connecting to Docker environments.

| Command | Description |
| --- | --- |
| `docker context ls` | List contexts |
| `docker context create` | Create a context |
| `docker context show` | Display the active context |
| `docker context use` | Switch contexts |
| `docker context inspect` | Inspect a context |
| `docker context update` | Update a context |
| `docker context rm` | Remove a context |
| `docker context export` | Export a context |
| `docker context import` | Import a context |

## 11. Configuration and Secrets

Commands for managing Swarm configurations and secrets.

| Command | Description |
| --- | --- |
| `docker config create` | Create a Swarm configuration |
| `docker config ls` | List configurations |
| `docker config inspect` | Inspect a configuration |
| `docker config rm` | Remove a configuration |
| `docker secret create` | Create a Swarm secret |
| `docker secret ls` | List secrets |
| `docker secret inspect` | Inspect a secret |
| `docker secret rm` | Remove a secret |

## 12. Plugins and Extensions

Commands for managing Docker plugins.

| Command | Description |
| --- | --- |
| `docker plugin ls` | List plugins |
| `docker plugin install` | Install a plugin |
| `docker plugin enable` | Enable a plugin |
| `docker plugin disable` | Disable a plugin |
| `docker plugin inspect` | Inspect a plugin |
| `docker plugin set` | Update plugin settings |
| `docker plugin upgrade` | Upgrade a plugin |
| `docker plugin rm` | Remove a plugin |

## 13. Security and Image Trust

Commands for image trust, vulnerability analysis, and debugging.

| Command | Description |
| --- | --- |
| `docker scout quickview` | Summarize image security information |
| `docker scout cves` | Review known vulnerabilities |
| `docker scout recommendations` | Review upgrade recommendations |
| `docker scout compare` | Compare image contents |
| `docker scout sbom` | View a software bill of materials |
| `docker trust key generate` | Generate a signing key |
| `docker trust sign` | Sign an image |
| `docker trust inspect` | Inspect image trust metadata |
| `docker trust revoke` | Revoke a signature |
| `docker debug` | Open a debugging shell for a container or image |

## 14. Development Utilities

Commands for initializing projects and managing additional Docker capabilities.

| Command | Description |
| --- | --- |
| `docker init` | Generate starter Docker project files |
| `docker checkpoint` | Manage container checkpoints |
| `docker desktop` | Manage Docker Desktop |
| `docker dhi` | Manage Docker Hardened Images |
| `docker model` | Manage Docker Model Runner |
| `docker mcp` | Manage MCP servers and clients |
| `docker offload` | Control Docker Offload |
| `docker pass` | Manage secrets in the local OS keychain |

## 15. General CLI Options and Help

Global options and commands useful across categories.

| Command or option | Description |
| --- | --- |
| `docker --help` | Show general help |
| `docker <command> --help` | Show command-specific help |
| `docker -v` | Show Docker CLI version |
| `docker -D` | Enable debug mode |
| `docker -H <host>` | Connect to a specified daemon |
| `docker --context <name>` | Use a specified context |
| `docker --config <dir>` | Use a specified configuration directory |
| `docker --log-level debug` | Set logging verbosity |
| `docker --tls` | Enable TLS |
| `docker --tlsverify` | Enable TLS and verify the remote |

## Quick Reference

| Task | Command |
| --- | --- |
| Start a container | `docker run -d nginx` |
| List running containers | `docker ps` |
| List all containers | `docker ps -a` |
| View logs | `docker logs <container>` |
| Open a shell | `docker exec -it <container> sh` |
| Build an image | `docker build -t myapp .` |
| List images | `docker images` |
| Remove a container | `docker rm <container>` |
| Remove an image | `docker rmi <image>` |
| Start Compose services | `docker compose up -d` |
| Stop Compose services | `docker compose down` |
| Inspect resource usage | `docker stats` |
| Check disk usage | `docker system df` |
| Clean unused resources | `docker system prune` |

> **Note:** This is a practical, purpose-based grouping, not Docker's official taxonomy. The commands shown are representative; subcommands and availability may vary by Docker version and installed plugins. Check `docker <command> --help` and the official documentation for exact syntax and current support.
