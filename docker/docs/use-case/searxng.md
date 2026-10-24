# SearXNG

## Installation

Minimal setup: one container from the official Docker Hub image (`searxng/searxng`), without a reverse proxy or Valkey.

### Prerequisites

- Docker Engine installed and running.
- Your user can run Docker commands (otherwise prefix them with `sudo`):

```console
sudo usermod -aG docker $USER
```

Log out and back in for the group change to apply.

### Run

```console
mkdir -p ./searxng/config ./searxng/data
cd searxng

docker run --name searxng -d \
    --restart unless-stopped \
    -p 8888:8080 \
    -v ./config:/etc/searxng \
    -v ./data:/var/cache/searxng \
    docker.io/searxng/searxng:latest
```

Open <http://localhost:8888>.

On the first start the container copies a default `settings.yml` into `config/` and replaces the placeholder secret key with a random one. Edit that file and restart the container to apply changes.

### Volumes

| Host path | Container path         | Purpose                          |
| --------- | ---------------------- | -------------------------------- |
| `config/` | `/etc/searxng`         | `settings.yml` and other config  |
| `data/`   | `/var/cache/searxng`   | Favicon cache and persistent data |

### Manage

```console
docker ps                        # show the running container
docker logs -f searxng           # follow logs
docker restart searxng           # apply config changes
docker stop searxng              # stop
docker rm searxng                # remove the container (volumes stay)
```

### Update

```console
docker pull searxng/searxng:latest
docker stop searxng && docker rm searxng
```

Then run the `docker run` command again. The mounted `config/` and `data/` directories are preserved.

### Notes

- Docker Hub rate-limits unauthenticated pulls. If you hit the limit, use the GHCR mirror: `ghcr.io/searxng/searxng`.
- Pin a version tag instead of `latest` for reproducible deployments.
- This setup is for local or private use. Before exposing SearXNG publicly, add a reverse proxy, the limiter, and a Valkey instance as described in the [official container guide](https://docs.searxng.org/admin/installation-docker.html).
