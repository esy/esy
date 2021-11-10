FROM alpine:latest

RUN apk add pkgconfig yarn make m4 git gcc g++ musl-dev perl perl-utils libbz2 zlib zlib-dev zlib-static autoconf automake bzip2-dev bzip2-static opam bash

RUN mkdir -p /app
COPY . /app/esy
WORKDIR /app/esy
RUN env LD_LIBRARY_PATH=/usr/lib make opam-setup SUDO=''
