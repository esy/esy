FROM ocaml/opam:centos as builder

USER root

WORKDIR /app/esy

RUN dnf -y install perl perl-utils

RUN dnf -y module install nodejs:12

RUN npm install --global yarn

COPY . /app/esy

RUN make new-docker OPAM_PREFIX_POST='flambda' SUDO=''

FROM centos:latest

RUN dnf -y install git perl perl-utils bzip2 gcc m4

COPY --from=builder /usr/local /usr/local
COPY --from=builder /app/_release /app/_release
