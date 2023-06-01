Esy_logs — Logging infrastructure for OCaml
-------------------------------------------------------------------------------
v0.7.0

Esy_logs provides a logging infrastructure for OCaml. Logging is performed
on sources whose reporting level can be set independently. Log message
report is decoupled from logging and is handled by a reporter.

A few optional log reporters are distributed with the base library and
the API easily allows to implement your own.

`Esy_logs` has no dependencies. The optional `Esy_logs_fmt` reporter on OCaml
formatters depends on [Fmt][fmt].  The optional `Esy_logs_browser`
reporter that reports to the web browser console depends on
[js_of_ocaml][jsoo]. The optional `Esy_logs_cli` library that provides
command line support for controlling Esy_logs depends on
[`Cmdliner`][cmdliner]. The optional `Esy_logs_lwt` library that provides
Lwt logging functions depends on [`Lwt`][lwt]

Esy_logs and its reporters are distributed under the ISC license.

[fmt]: http://erratique.ch/software/fmt
[jsoo]: http://ocsigen.org/js_of_ocaml/
[cmdliner]: http://erratique.ch/software/cmdliner
[lwt]: http://ocsigen.org/lwt/

Home page: http://erratique.ch/software/esy_logs

## Installation

Esy_logs can be installed with `opam`:

    opam install esy_logs
    opam install fmt cmdliner lwt js_of_ocaml esy_logs # Install all opt libraries

If you don't use `opam` consult the [`opam`](opam) file for build
instructions.

## Documentation

The documentation can be consulted [online][doc] or via `odig doc esy_logs`. 

[doc]: http://erratique.ch/software/esy_logs/doc/

## Sample programs

If you installed Esy_logs with `opam` sample programs are located in
the directory `opam config var esy_logs:doc`.


