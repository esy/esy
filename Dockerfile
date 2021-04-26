FROM ocaml/opam:alpine-3.12-ocaml-4.10 as builder

WORKDIR /app/esy

RUN sudo apk add pkgconfig yarn make m4 git gcc g++ musl-dev perl perl-utils autoconf automake bzip2 bzip2-dev zlib zlib-dev

RUN opam repository add duniverse https://github.com/dune-universe/opam-repository.git#duniverse

COPY esy.opam /app/esy
RUN opam install . --deps-only -y

RUN mkdir -p /app
COPY . /app/esy
RUN sudo chown -R opam:opam /app/esy

RUN opam exec -- dune build -p esy
RUN opam exec -- dune build @install
RUN opam exec -- sudo dune install --prefix /usr/local
RUN opam clean

RUN git -C /app/esy/esy-solve-cudf apply static-linking.patch && \
    git -C /app/esy apply static-linking.patch

RUN esy i --ocaml-pkg-name ocaml --ocaml-version 4.10.1002-musl.static.flambda && \
    esy b --ocaml-pkg-name ocaml --ocaml-version 4.10.1002-musl.static.flambda && \
    esy cleanup . && \
    esy release --static --no-env --ocaml-pkg-name ocaml --ocaml-version 4.10.1002-musl.static.flambda

RUN opam exec -- sudo dune uninstall --prefix /usr/local
RUN sudo yarn global --prefix=/usr/local --force add $PWD/_release
RUN sudo mv _release /app/_release

FROM ocaml/opam:alpine-3.12-ocaml-4.10

COPY --from=builder /usr/local /usr/local
COPY --from=builder /app/_release /app/_release
