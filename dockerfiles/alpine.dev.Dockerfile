# Image must be named esydev/esy-builder
FROM alpine:latest as builder

RUN apk add pkgconfig yarn make m4 git gcc g++ musl-dev perl perl-utils libbz2 zlib zlib-dev zlib-static autoconf automake bzip2-dev bzip2-static opam bash
WORKDIR /app-builder
COPY ./scripts/opam.sh /app-builder/opam.sh
RUN /app-builder/opam.sh init


