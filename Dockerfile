FROM alpine:latest

COPY . /app/esy
WORKDIR /app/esy
RUN apk add opam yarn make m4 git gcc g++ musl-dev perl perl-utils && \
 git -C /app/esy/esy-solve-cudf apply static-linking.patch && \
 git -C /app/esy apply static-linking.patch && \
 opam init -y --disable-sandboxing --bare && \
 opam switch create esy-local-switch 4.10.1+musl+static+flambda -y && \ 
 opam repository add duniverse https://github.com/dune-universe/opam-repository.git#duniverse && \
 opam install . --deps-only -y && \
 opam exec -- dune build -p esy && \
 opam exec -- dune build @install && \
 opam exec -- dune install --prefix /usr/local && \
 esy i --ocaml-pkg-name ocaml --ocaml-version 4.10.1002-musl.static.flambda && \
 esy b --ocaml-pkg-name ocaml --ocaml-version 4.10.1002-musl.static.flambda && \
 esy release --static  --ocaml-pkg-name ocaml --ocaml-version 4.10.1002-musl.static.flambda && \
 opam exec -- dune uninstall --prefix /usr/local && \
 yarn global --prefix=/usr/local --force add $PWD/_release && \
 mv _release /app/_release && \
 rm -rf /app/esy && \
 rm -rf /root/.opam && \
 rm -rf /root/.esy && \
 apk del opam m4 gcc g++ musl-dev yarn