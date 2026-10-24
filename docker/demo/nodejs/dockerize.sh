#!/usr/bin/env bash

set -a
source .env
set +a

IMAGE_NAME="hello_world_bun"

pipe() {
    docker compose build \
    --pull -t \
    "$IMAGE_NAME" .

    docker run --rm \
    --env-file .env \
    -p "$PORT:$PORT" \
    "$IMAGE_NAME"
}

rm_img() {
    docker rmi "$IMAGE_NAME"
}

"$1"
