FROM alpine:latest

RUN apk add opam make m4 git gcc g++ musl-dev perl perl-utils
COPY . /app/esy
WORKDIR /app/esy
RUN opam init -y --disable-sandboxing --bare
RUN opam switch create esy-local-switch ocaml-base-compiler.4.10.1 -y
RUN opam install . --deps-only -y
RUN opam exec -- dune build -p esy
RUN opam exec -- dune build @install
RUN opam exec -- dune install --prefix /usr/local
RUN esy 
RUN esy release
RUN mv _release /app/_release
RUN rm -rf /app/esy
RUN rm -rf ~/.opam