---
id: docker-and-static-linking
title: "Docker and static linking"
---

## Docker image

`esy` is currently available as an alpine image only. See [Docker
Hub][] for the complete list.

## Static linking

The alpine image can be used to build statically link Reason/OCaml
binaries. Here's an example Docker image.

```Dockerfile
FROM esydev/esy:nightly-alpine-latest

COPY package.json package.json
COPY esy.lock esy.lock
RUN esy i
RUN esy build-dependencies
COPY hello.ml hello.ml
RUN esy

ENTRYPOINT ["/entrypoint.sh"]
```

The `package.json` / `esy.json` must use a compiler version that uses
`musl-libc`. `4.10.1002-musl.static.flambda` is one such versions.

The statically linked binaries can be copied out of the container with
`docker cp`.

Here's a same github action job doing so.

```
static-build:
  runs-on: ubuntu-latest
  steps:
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3
    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        file: ./Dockerfile
        push: false
        tags: user/app:latest
    - run: |
        docker container run --pull=never -itd --network=host --name "<CONTAINER_NAME>" "<IMAGE:TAG>"
        docker cp "<CONTAINER_NAME>:/path/to/built/binary" "<HOST_PATH>/binary"
      name: "Copy artifacts from /usr/local/ in the container"
```

[Docker Hub]: https://hub.docker.com/r/esydev/esy
