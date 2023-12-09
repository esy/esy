# Image must be named esydev/esy-builder
FROM alpine:latest as builder

RUN apk update
RUN apk add pkgconfig yarn make m4 git gcc g++ musl-dev perl perl-utils libbz2 zlib zlib-dev zlib-static autoconf automake bzip2-dev bzip2-static bash curl openssl patch
RUN bash -c "sh <(curl -fsSL https://raw.githubusercontent.com/ocaml/opam/master/shell/install.sh) --download-only" && mv opam-2.1.5-x86_64-linux /usr/local/bin/opam && chmod u+x /usr/local/bin/opam
WORKDIR /app-builder
COPY ./scripts/opam.sh /app-builder/opam.sh
RUN /app-builder/opam.sh init


