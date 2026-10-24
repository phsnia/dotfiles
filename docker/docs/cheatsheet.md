# Docker Cheat Sheet

## Table of contents
* [Status and information](##Status_and_information)
* [Manage containers](##Manage_container)
[Manage Docker images]
[Containers with ports, names, and volumes]

## Status and information
```
docker -verison: 
  Check docker version 

docker info
  Show docker system information

docker help:
  List available
  
docker <command> --help
  Show help for a specific command
```

## Manage container
```
docker ps
  List running containers

docker ps -a
  List all containers, including stopped ones

docker run nginx
  Create and start an Nginx container

docker run -d nginx
  Run a container in the background

docker run -d --name web nginx
  Start a container with a custom name

docker start <container>
  Start a stopped container

docker stop <container>
  Stop a running container

docker restart <container>
  Restart a container

docker rm <container>
  Remove a stopped container

docker rm -f <container>
  Force-remove a container

docker logs <container>
  View container logs

docker logs -f <container>
  Follow live logs

docker inspect <container>
  View detailed container configuration

docker stats
  View live CPU and memory usage
```

## Docker images
```
docker images
  List local images

docker pull nginx
  Download an image

docker build -t myapp .
  Build an image from a Dockerfile

docker tag myapp myapp:v1
  Add a tag to an image

docker rmi <image>
  Remove an image

docker image inspect nginx
  Inspect image details

docker history nginx
  View image build layers

docker push <image>
  Push an image to a registry
```
