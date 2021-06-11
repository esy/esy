FROM alpine:latest as builder

RUN apk add pkgconfig yarn make m4 git gcc g++ musl-dev perl perl-utils libbz2 zlib zlib-dev zlib-static autoconf automake bzip2-dev bzip2-static opam

RUN mkdir -p /app
COPY . /app/esy
COPY esy.opam /app/esy

WORKDIR /app/esy

RUN env LD_LIBRARY_PATH=/usr/lib make new-docker SUDO=''

FROM alpine:latest

COPY --from=builder /usr/local /usr/local
COPY --from=builder /app/_release /app/_release
