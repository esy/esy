(lang dune 2.0)
(using menhir 2.0)
(name esy)

(allow_approximate_merlin)

(license MIT)
(maintainers
 "Manas Jayanth <prometheansacrifice@gmail.com>"
 "Andrey Popp <8mayday@gmail.com>")
 
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
 (description "
Easy package management for native Reason, OCaml and more
")
 (depends
    angstrom
    cmdliner
    bos 
    (cudf (= 0.9+dune))  
    (dose3 (= 5.0.1+dune))
    (ocamlgraph (= 1.8.8+dune))
    dune  
    fmt  
    fpath  
    lambda-term  
    logs  
    lwt  
    reason
    lwt_ppx
    junit
    (menhir (= 20200211)) 
    (ocamlformat (= 0.15.0)) 
    opam-core  
    opam-file-format  
    opam-format  
    opam-state  
    ppx_deriving  
    ppx_deriving_yojson
    ppx_expect  
    ppx_inline_test  
    ppx_let  
    ppx_sexp_conv  
    re  
    mccs
    yojson  
    (ocaml (= 4.10.2))
    (extlib (< 1.7.8))))

