(lang dune 3.16)
(using menhir 2.0)
(name esy)

(license BSD-2-Clause)
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
    uuseg
    (cmdliner (= dev))
    (bos (= dev))
    cudf
    (dose3 (= 7.0.0))
    (ocamlgraph (= 2.0.0))
    dune  
    fmt  
    fpath  
    lambda-term  
    logs  
    lwt  
    reason
    (cli (= dev))
    (pastel (= dev))
    (file-context-printer (= dev))
    lwt_ppx
    junit
    (menhir (= 20210419)) 
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
    (ocaml (= 5.2.0))
    extlib))

