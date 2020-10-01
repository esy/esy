(lang dune 2.0)
(using menhir 2.0)
(name esy)

(allow_approximate_merlin)

(license MIT)
(maintainers
 Manas Jayanth <prometheansacrifice@gmail.com>
 Andrey Popp <8mayday@gmail.com>)
 
(authors
 "Andrey Popp <8mayday@gmail.com>"
 "Manas Jayanth <prometheansacrifice@gmail.com>"
 "Ulrik Strid <ulrik.strid@outlook.com>"
 "Bryan Phelps <bryphe@outrunlabs.com>"
 "Eduardo Rafael <theeduardorfs@gmail.com>")

(source (github esy/esy))

(generate_opam_files true)

(package
 (name esy)
 (synopsis "A package.json driven package manager for Reason and OCaml")
 (description "LSP protocol implementation in OCaml")
 (depends
    angstrom
    cmdliner
    bos
    (cudf  (= 0.9))
    (dose3  (= 5.0.1))
    (dune  (= 2.6.0))
    (fmt  (= 0.8.8))
    (fpath  (= 0.7.2))
    (lambda-term  (= 2.0.2))
    (logs  (= 0.7.0))
    (lwt  (= 4.4.0))
    (lwt_ppx  (= 1.2.4))
    (menhir  (= 20200211))
    (ocamlformat  (= 0.15.0))
    (opam-core  (= 2.0.5))
    (opam-file-format  (= 2.0.0))
    (opam-format  (= 2.0.5))
    (opam-state  (= 2.0.5))
    (ppx_deriving  (= 4.5))
    ppx_deriving_yojson
    (ppx_expect  (= v0.13.1))
    (ppx_inline_test  (= v0.13.0))
    (ppx_let  (= v0.13.0))
    (ppx_sexp_conv  (= v0.13.0))
    (re  (= 1.9.0))
    reason 
    mccs
    (yojson  (= 1.7.0 ))
    (ocaml  (>= 4.10.0 ))))

