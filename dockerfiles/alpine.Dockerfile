FROM alpine:latest as builder

RUN apk add pkgconfig yarn make m4 git gcc g++ musl-dev perl perl-utils libbz2 zlib zlib-dev zlib-static autoconf automake bzip2-dev bzip2-static opam bash

RUN mkdir -p /app
COPY . /app/esy
COPY esy.opam /app/esy

WORKDIR /app/esy

# This section useful for debugging the image/container
# RUN env LD_LIBRARY_PATH=/usr/lib make opam-setup SUDO=''
# RUN env LD_LIBRARY_PATH=/usr/lib make build-with-opam SUDO=''
# RUN env LD_LIBRARY_PATH=/usr/lib make build-with-esy SUDO=''
# RUN env LD_LIBRARY_PATH=/usr/lib make opam-cleanup SUDO=''
# RUN env LD_LIBRARY_PATH=/usr/lib make install-esy-artifacts SUDO=''

# The statements above cannot be used as is because CI disks run out of space
# Which is why we use a single command that builds and cleans up in the same run step.
# This is because docker caches results of multiple steps - having everything in one step
# (that also cleans up build cache) takes lesser space.
RUN env LD_LIBRARY_PATH=/usr/lib make new-docker SUDO=''

# FROM alpine:latest

# COPY --from=builder /usr/local /usr/local
# COPY --from=builder /app/_release /app/_release
