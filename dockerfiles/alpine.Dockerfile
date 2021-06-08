FROM alpine:latest as builder

RUN mkdir -p /app
COPY . /app/esy
COPY esy.opam /app/esy

WORKDIR /app/esy

RUN apk add pkgconfig opam yarn make m4 git gcc g++ musl-dev perl perl-utils

RUN make new-docker SUDO=''

FROM alpine:latest

COPY --from=builder /usr/local /usr/local
COPY --from=builder /app/_release /app/_release
