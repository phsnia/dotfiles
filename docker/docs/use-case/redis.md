# Redis/Valkey

### Prerequisites
- Docker Engine installed and running.
- Your user can run Docker commands (otherwise prefix them with `sudo`).

```cmd
docker login dhi.io
```

```console
mkdir -p ./redis-stack/data
cd redis-stack

docker run --name redis-stack -d \
    --restart unless-stopped \
    -p 127.0.0.1:6379:6379 \
    -p 127.0.0.1:8001:8001 \
    -v ./data:/data \
    -e REDIS_ARGS="--appendonly yes --requirepass 123456" \
    redis/redis-stack:latest
```

Open a Redis CLI session
```
docker exec -it redis redis-cli
```
