# Building Images

Reference:
* [Building Images Official](https://docs.docker.com/get-started/docker-concepts/building-images)
* [Official Docker: Understanding Image Layers](https://docs.docker.com/get-started/docker-concepts/building-images/understanding-image-layers)

This guide covers the core concepts for building production-ready images: image layers, writing a Dockerfile, building/tagging/publishing, the build cache, and multi-stage builds.

## 1. Understanding Image Layers

A container image is composed of layers, and each layer is immutable once created. Each layer represents a set of filesystem changes: additions, deletions, or modifications.

A theoretical Python app image might be built from these layers:

1. Base commands and a package manager (such as `apt`)
2. A Python runtime and `pip`
3. The application's `requirements.txt`
4. The application's dependencies
5. The application's source code

Layering lets images share layers. A second Python app can reuse the same Python base layers, which makes builds faster and reduces storage and bandwidth when distributing images.

### How the layers stack

Layering is made possible by content-addressable storage and union filesystems:

1. After each layer is downloaded, it's extracted into its own directory on the host filesystem.
2. When you run a container, a union filesystem stacks the layers on top of each other into a unified view.
3. When the container starts, its root directory is set to that unified directory using `chroot`.

In addition to the image layers, the union filesystem includes a writable directory specific to the running container. All container filesystem changes happen there, leaving the original image layers untouched. This is what allows multiple containers to run from the same underlying image.

### Building layers manually with `commit`

You'll rarely build images this way — you'll normally use a Dockerfile — but `docker container commit` makes the layering model easy to see:

```console
$ docker run --name=base-container -ti ubuntu
root@d8c5ca119fcd:/# apt update && apt install -y nodejs
```

In another terminal, save the container's changes as a new image layer:

```console
$ docker container commit -m "Add node" base-container node-base
```

Inspect the layers with `docker image history`:

```console
$ docker image history node-base

IMAGE          CREATED          CREATED BY                                      SIZE      COMMENT
9e274734bb25   10 seconds ago   /bin/bash                                       157MB     Add node
cd1dba651b30   7 days ago       /bin/sh -c #(nop)  CMD ["/bin/bash"]            0B
<missing>      7 days ago       /bin/sh -c #(nop) ADD file:6089c6bede9eca8ec…   110MB
```

The top layer with the "Add node" comment contains the Node.js install. You can extend this base image with more layers the same way, and even set the default command at commit time:

```console
$ docker container commit -c "CMD node app.js" -m "Add app" app-container sample-app
```

> **Base image**
>
> A base image is a foundation for building other images. Any image can serve as a base, though some images are intentionally created as building blocks. A `node-base` image like the one above isn't useful to deploy on its own, but it's a reusable starting point for other builds.

## 2. Writing a Dockerfile

A Dockerfile is a text-based document used to create a container image. It tells the image builder which commands to run, which files to copy, the startup command, and more.

```dockerfile
FROM python:3.13
WORKDIR /usr/local/app

# Install the application dependencies
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy in the source code
COPY src ./src
EXPOSE 8080

# Setup an app user so the container doesn't run as the root user
RUN useradd app
USER app

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

### Common instructions

| Instruction | Description |
| --- | --- |
| `FROM <image>` | The base image that the build extends |
| `WORKDIR <path>` | The working directory where files are copied and commands run |
| `COPY <host-path> <image-path>` | Copy files from the host into the image |
| `RUN <command>` | Run a command during the build |
| `ENV <name> <value>` | Set an environment variable for the running container |
| `EXPOSE <port-number>` | Declare a port the image would like to expose |
| `USER <user-or-uid>` | Set the default user for all subsequent instructions |
| `CMD ["<command>", "<arg1>"]` | The default command a container from this image runs |

See the [Dockerfile reference](https://docs.docker.com/reference/dockerfile/) for the full list of instructions.

### A minimal example

A Dockerfile typically follows these steps: choose a base image, install dependencies, copy in source code, configure the final image. For a Node.js app:

```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY . .
RUN yarn install --production
CMD ["node", "./src/index.js"]
```

Notes:

- The `Dockerfile` has **no file extension** — some editors will add one or complain about its absence.
- This Dockerfile builds successfully but isn't production-ready: it doesn't maximize the build cache, and it runs as root. The following sections fix both.

## 3. Build, Tag, and Publish

### Building

The most basic build command is:

```console
$ docker build .
```

The final `.` is the path to the [build context](https://docs.docker.com/build/concepts/context/#what-is-a-build-context) — the location where the builder finds the `Dockerfile` and any referenced files. When you run a build, the builder pulls the base image if needed, then runs the Dockerfile instructions.

Without a tag, the resulting image is referenced only by its `sha256:` ID, which is hardly memorable. The builder output shows each instruction as it executes:

```console
$ docker build .
[+] Building 3.5s (11/11) FINISHED                                              docker:desktop-linux
 => [internal] load build definition from Dockerfile                                            0.0s
 => [internal] load metadata for docker.io/library/python:3.12                                  0.0s
 => [1/6] FROM docker.io/library/python:3.12                                                    0.0s
 => [2/6] WORKDIR /usr/local/app                                                                0.0s
 => [3/6] RUN useradd app                                                                       0.1s
 => [4/6] COPY ./requirements.txt ./requirements.txt                                            0.0s
 => [5/6] RUN pip install --no-cache-dir --upgrade -r requirements.txt                          3.2s
 => [6/6] COPY ./app ./app                                                                      0.0s
 => exporting to image                                                                          0.1s
 => => writing image sha256:9924dfd9350407b3df01d1a0e1033b1e543523ce7d5d5e2c83a724480ebe8f00
```

### Tagging

Tagging gives an image a memorable name. A full image name has the structure:

```text
[HOST[:PORT_NUMBER]/]PATH[:TAG]
```

| Component | Description |
| --- | --- |
| `HOST` | Optional registry hostname; defaults to Docker's public registry `docker.io` |
| `PORT_NUMBER` | Registry port number, if a hostname is provided |
| `PATH` | Slash-separated image path; on Docker Hub, `[NAMESPACE/]REPOSITORY`. Defaults to the `library` namespace (Docker Official Images) |
| `TAG` | Human-readable identifier for versions or variants; defaults to `latest` |

Examples:

- `nginx` → `docker.io/library/nginx:latest`
- `docker/welcome-to-docker` → `docker.io/docker/welcome-to-docker:latest`
- `ghcr.io/dockersamples/example-voting-app-vote:pr-311` → GitHub Container Registry, `dockersamples` namespace, tag `pr-311`

Tag during a build with `-t` / `--tag`:

```console
$ docker build -t my-username/my-image .
```

Or add a tag to an existing image:

```console
$ docker image tag my-username/my-image another-username/another-image:v1
```

### Publishing

Push the tagged image to a registry:

```console
$ docker push my-username/my-image
```

> **Authentication required**
>
> You must be logged in before pushing to a repository. Use `docker login` first. If you see `requested access to the resource is denied`, check that you're logged in and that the image tag matches your username.

To verify a published build, inspect it locally:

```console
$ docker image ls
REPOSITORY                             TAG       IMAGE ID       CREATED          SIZE
mobywhale/concepts-build-image-demo    latest    746c7e06537f   24 seconds ago   354MB

$ docker image history mobywhale/concepts-build-image-demo
```

The history output shows the layers you added on top of those inherited from your base image.

## 4. Using the Build Cache

Docker executes each Dockerfile instruction in order, creating a layer for each. For every instruction, Docker checks whether it can reuse the result of a similar instruction from a previous build. If it can, the cached result is used and the step is skipped.

### Cache invalidation

To maximize cache usage, understand what invalidates it:

- **Changes to a `RUN` command** invalidate that layer and everything after it.
- **Changes to files copied with `COPY` or `ADD`** — Docker watches the copied files, and content or property changes (like permissions) trigger invalidation.
- **Cascade:** once one layer is invalidated, every following layer is invalidated too.

### Ordering instructions for cache hits

Given a naive Dockerfile, any source change invalidates the `COPY . .` layer and forces the expensive dependency install to re-run:

```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY . .
RUN yarn install --production
EXPOSE 3000
CMD ["node", "./src/index.js"]
```

Restructure it so dependencies are only reinstalled when the manifest changes — copy the manifest first, install, then copy the rest:

```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --production
COPY . .
EXPOSE 3000
CMD ["node", "src/index.js"]
```

Also add a `.dockerignore` file to keep unnecessary files out of the build context:

```plaintext
node_modules
```

Now, after editing only source files (for example `src/static/index.html`), the rebuild shows cached steps:

```console
$ docker build -t node-app:3.0 .
[+] Building 1.2s (10/10) FINISHED
 => [1/5] FROM docker.io/library/node:22-alpine                                                    0.0s
 => CACHED [2/5] WORKDIR /app                                                                      0.0s
 => CACHED [3/5] COPY package.json yarn.lock ./                                                    0.0s
 => CACHED [4/5] RUN yarn install --production                                                     0.0s
 => [5/5] COPY . .                                                                                 0.5s
```

The dependency install step — previously ~14 seconds — is now instant. Because the changed layers are only near the top, pushing and pulling the updated image is also much faster.

## 5. Multi-Stage Builds

In a traditional build, every step (downloading dependencies, compiling, packaging) runs in a single build container, and all of it ends up in the final image — bloating it and increasing the security risk. Multi-stage builds introduce multiple stages in a Dockerfile, each with a specific purpose, so the build environment is separated from the runtime environment.

This helps both:

- **Interpreted languages** (JavaScript, Python, Ruby): build and minify in one stage, copy production-ready files to a smaller runtime image.
- **Compiled languages** (C, Go, Rust): compile in one stage, copy only the compiled binaries into the final image — no compiler in production.

### Structure

Multiple `FROM` statements define stages, `AS <stage-name>` names them, and `COPY --from=<stage>` pulls files across stages:

```dockerfile
# Stage 1: Build Environment
FROM builder-image AS build-stage
# Install build tools (e.g., Maven, Gradle)
# Copy source code
# Build commands (e.g., compile, package)

# Stage 2: Runtime environment
FROM runtime-image AS final-stage
COPY --from=build-stage /path/in/build/stage /path/to/place/in/final/stage
# Define runtime configuration (e.g., CMD, ENTRYPOINT)
```

### Example: Spring Boot

A single-stage Dockerfile for a Maven Spring Boot app:

```dockerfile
FROM eclipse-temurin:21.0.8_9-jdk-jammy
WORKDIR /app
COPY .mvn/ .mvn
COPY mvnw pom.xml ./
RUN ./mvnw dependency:go-offline
COPY src ./src
CMD ["./mvnw", "spring-boot:run"]
```

```console
$ docker build -t spring-helloworld .
$ docker images
REPOSITORY          TAG       IMAGE ID       CREATED          SIZE
spring-helloworld   latest    ff708d5ee194   3 minutes ago    880MB
```

880MB — it ships the full JDK and Maven toolchain, which production doesn't need. The multi-stage version builds with the JDK, then runs on a JRE-only image:

```dockerfile
FROM eclipse-temurin:21.0.8_9-jdk-jammy AS builder
WORKDIR /opt/app
COPY .mvn/ .mvn
COPY mvnw pom.xml ./
RUN ./mvnw dependency:go-offline
COPY ./src ./src
RUN ./mvnw clean install

FROM eclipse-temurin:21.0.8_9-jre-jammy AS final
WORKDIR /opt/app
EXPOSE 8080
COPY --from=builder /opt/app/target/*.jar /opt/app/*.jar
ENTRYPOINT ["java", "-jar", "/opt/app/*.jar"]
```

```console
$ docker build -t spring-helloworld-builder .
$ docker images
REPOSITORY                  TAG       IMAGE ID       CREATED              SIZE
spring-helloworld-builder   latest    c5c76cb815c0   24 minutes ago       428MB
spring-helloworld           latest    ff708d5ee194   About an hour ago    880MB
```

The final image drops from 880MB to 428MB with the same functionality — smaller, more secure, and easier to manage.

> **Build target**
>
> The last stage is the default build target. To build only a specific stage, use `docker build --target <stage>`:
>
> ```console
> $ docker build -t spring-helloworld-builder --target builder .
> ```

> **Production Java tip**
>
> For production use, prefer creating a custom runtime with `jlink` containing only the Java modules your application needs, which further reduces size and attack surface. See [eclipse-temurin on Docker Hub](https://hub.docker.com/_/eclipse-temurin).

## Command Quick Reference

| Task | Command |
| --- | --- |
| Build an image from a Dockerfile | `docker build .` |
| Build and tag | `docker build -t user/image .` |
| Build a specific stage | `docker build --target <stage> .` |
| List images | `docker image ls` |
| Show layers and history | `docker image history <image>` |
| Add a tag to an existing image | `docker image tag <src> <target>` |
| Push an image | `docker push <image>` |
| Save an image to an archive | `docker image save <image> -o <file>.tar` |
| Commit a container as an image | `docker container commit <container> <image>` |

## Additional Resources

* [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
* [Dockerfile best practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
* [Base images](https://docs.docker.com/build/building/base-images/)
* [What is a build context?](https://docs.docker.com/build/concepts/context/)
* [Multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
* [Build cache management](https://docs.docker.com/build/cache/)
* [Build cache invalidation](https://docs.docker.com/build/cache/invalidation/)
