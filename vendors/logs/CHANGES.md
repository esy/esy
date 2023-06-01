v0.7.0 2019-08-09 Zagreb
------------------------

Support for thread safe logging, thanks to Jules Aguillon for the
work.

* Add `Esy_logs.set_reporter_mutex` for installing mutual exclusion
  primitives to access the reporter.
* Add `Esy_logs_threaded.enable` to install mutual exclusion
  primitives for OCaml threads.

v0.6.3 2019-04-19 La Forclaz (VS)
---------------------------------

* Make the package compatible with `js_of_ocaml` 3.3.0's
  namespacing. Thanks to Hugo Heuzard for the patch.
* Fix toplevel initialisation for `Omod` (#21).
* Fix 4.08 `Pervasives` deprecation.
* Drop support for ocaml < 4.03.0
* Doc: various improvements and typo fixing.

v0.6.2 2016-08-10 Zagreb
------------------------

* 4.04.0 compatibility. Thanks to Damien Doligez for the patch.


v0.6.1 2016-06-08 Cambridge (UK)
--------------------------------

* Fix esy_logs.top package on case sensitive file systems.

v0.6.0 2016-05-23 La Forclaz (VS)
---------------------------------

* Build depend on topkg.
* Relicensed from BSD3 to ISC.
* Revise the command line interface provided by `Esy_logs_cli`. Removes
  the argument from option `-v`. See issue #13 for details.
* Add `Esy_logs.format_reporter` a reporter like `Esy_logs_fmt.reporter`
  but without colors and hence without the dependency on `Fmt`.
  Thanks to Simon Cruanes for the suggestion.
* `Esy_logs_fmt.reporter`, the optional argument `prefix` is changed to
  `pp_header` and becomes a formatter. The default prefix now favors
  the basename of `Sys.argv.(0)` if it exists over
  `Sys.executable_name`; this gives better results for interpreted
  programs.
* Fix colors in `Esy_logs_fmt.pp_header`, only `Esy_logs.err_style` was
  being used.
* Add `Esy_logs.level_{of,to}_string`.


v0.5.0 2016-01-07 La Forclaz (VS)
---------------------------------

* Support for OCaml 4.01.0
* Change the logging structure from `Esy_logs.err fmt (fun m -> m ...)`
  to `Esy_logs.err (fun m -> m fmt ...)`. See the documentation basics
  for more details. Thanks to Edwin Török for suggesting this.
* Remove the `Esy_logs.unit[_msgf]` functions, they are no longer needed.
* Rename the `Esy_logs_stdo` library to `Esy_logs_fmt`.
* Changes the signature of reporters to take a callback function to
  call unconditionally once the report is over. Thanks to Edwin Török
  for suggesting the mecanism.
* Add the optional `Esy_logs_lwt` library. Provides logging functions
  returning `lwt` threads that proceed only once the report is over.
* Add `Esy_logs_fmt.pp_header` and `Esy_logs_fmt.{err_warn,info_debug}_style`.
* Add `Esy_logs.pp_{level,header}`.


v0.4.2 2015-12-03 Cambridge (UK)
--------------------------------

First release.
