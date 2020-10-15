FROM alpine:latest

RUN apk add opam make m4 git gcc g++ musl-dev perl perl-utils
COPY . /app/esy
WORKDIR /app/esy
RUN opam init -y --disable-sandboxing --bare && \
 opam switch create esy-local-switch 4.10.1+musl+static+flambda -y && \ 
 opam repository add duniverse https://github.com/dune-universe/opam-repository.git#duniverse && \
 opam install . --deps-only -y && \
 opam exec -- dune build -p esy && \
 opam exec -- dune build @install && \
 opam exec -- dune install --prefix /usr/local && \
 esy  && \
 esy release && \
 mv _release /app/_release && \
 rm -rf /app/esy && \
 rm -rf /root/.opam && \
 rm -rf /root/.esy