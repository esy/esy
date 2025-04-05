FROM alpine:latest AS builder

RUN apk add pkgconfig yarn make m4 git gcc g++ musl-dev perl perl-utils libbz2 zlib zlib-dev zlib-static autoconf automake bzip2-dev bzip2-static opam bash
WORKDIR /app-builder
COPY ./scripts/opam.sh /app-builder/opam.sh
RUN /app-builder/opam.sh init

WORKDIR /app
COPY esy.opam /app
COPY esy.opam.locked /app
COPY ./scripts /app/scripts
RUN /app/scripts/opam.sh install

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
COPY ./bin /app/bin
# We need .git to find esy version.
# It's possible to do without it, but will need an additional,
# `esy i && esy b dune build @esy-version/all && cp _build/default/esy-version/EsyVersion.re esy-version/`
# to generate and copy the EsyVersion.re file
COPY ./esy-shell-expansion /app/esy-shell-expansion
COPY ./esy-version /app/esy-version
COPY ./esy-opam /app/esy-opam
COPY ./esy-solve /app/esy-solve
COPY ./esy-fetch /app/esy-fetch
COPY ./esy-install-npm-release /app/esy-install-npm-release
COPY ./esy-solve-cudf /app/esy-solve-cudf
COPY ./esy-primitives /app/esy-primitives
COPY ./esy-build /app/esy-build
COPY ./esy-lib /app/esy-lib
COPY ./esy-build-package /app/esy-build-package
COPY ./esy-command-expression /app/esy-command-expression
COPY ./esy-package-config /app/esy-package-config
COPY ./esy-rewrite-prefix /app/esy-rewrite-prefix
COPY ./esy-runtime /app/esy-runtime
COPY dune /app/
COPY dune-project /app/
COPY dune-workspace /app/
COPY esy.json /app/esy.json
COPY esy.lock /app/esy.lock
COPY ./fastreplacestring /app/fastreplacestring
RUN /app/scripts/opam.sh build
RUN /app/scripts/opam.sh install-artifacts

FROM alpine:latest
COPY --from=builder /usr/local /usr/local
RUN apk add nodejs npm linux-headers curl git perl-utils bash gcc g++ musl-dev make m4 patch
