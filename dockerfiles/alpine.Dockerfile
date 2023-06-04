FROM alpine:latest as builder

WORKDIR /app

RUN apk add pkgconfig yarn make m4 git gcc g++ musl-dev perl perl-utils libbz2 zlib zlib-dev zlib-static autoconf automake bzip2-dev bzip2-static opam bash

COPY esy.opam /app
COPY esy.opam.locked /app
COPY Makefile /app
WORKDIR /app
RUN make opam-setup

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
COPY ./esy-shell-expansion /app/esy-shell-expansion
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
COPY dune /app/
COPY dune-project /app/
COPY dune-workspace /app/
COPY esy.json /app/esy.json
COPY esy.lock /app/esy.lock
COPY static.json /app/static.json
COPY static.esy.lock /app/static.esy.lock
COPY ./vendors /app/vendors
COPY ./fastreplacestring /app/fastreplacestring
RUN make build-with-opam && make dune-cleanup && make opam-cleanup

FROM alpine:latest

COPY --from=builder /usr/local /usr/local
RUN apk add nodejs npm linux-headers curl git perl-utils bash gcc g++ musl-dev make m4 patch
