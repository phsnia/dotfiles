#!/bin/bash

_1() {
    remove_container_if_exists() {
        local name="$1"

        if docker container inspect "$name" >/dev/null 2>&1; then
            docker rm -f "$name"
        fi
    }

    echo "==> Check container is existed"
    remove_container_if_exists hello
    echo "==> Creating container..."
    docker create --name hello alpine echo "Hello World"
    echo "==> Start container"
    docker start -ai hello
}

"$1"
