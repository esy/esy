

* Add `Fmt.if'`, thanks to Rizo for the suggestion and patch.

v0.9.0 2021-10-22 Zagreb
------------------------

* Add alert messages to deprecation annotations (#47).
* The solution using ephemerons introduced in v0.8.7 for attaching
  custom data to formatters has unreliable performance characteristics
  in some usage scenarios. Namely use of `Fmt.styled` with
  `Fmt.[k]str` heavy code as those rely on `Format.{k,a}sprintf` which
  allocate one formatter per call. 
  
  Hence we subvert again the `Format` tag system to do dirty
  things. However since as of 4.08 tags became an extensible sum type
  we can keep our dirty things entirely internal.

  Thanks to Thomas Leonard for reporting and David Kaloper Meršinjak
  for further investigations (#52).
  
v0.8.10 2021-10-04 Zagreb
-------------------------

* Require OCaml >= 4.08. This drops the dependency on the 
  `stdlib-shims` and `seq` packages.
* Add the `[@@ocaml.deprecated]` annotation to deprecated 
  functions. Thanks to Antonin Décimo for the patch.

v0.8.9 2020-09-23 Zagreb
------------------------

* Fix `Dump.{iter_bindings,hashtbl}` which since 0.8.7 no longer 
  prints seperators. Thanks to Edwin Török for the patch.
* Open the result of `Fmt.error_msg` to make it easier
  to compose with other errors. Thanks to Thomas Leonard 
  for the patch.

v0.8.8 2019-08-01 Zagreb
------------------------

Fix build on 32-bit platforms.

v0.8.7 2019-07-21 Zagreb
------------------------

* Require OCaml 4.05.
* Add `Fmt.hex` and friends. Support for hex dumping.
  Thanks to David Kaloper Meršinjak for the design and implementation..
* Add `Fmt.si_size` to format integer magnitudes using SI prefixes.
* Add `Fmt.uint64_ns_span` to format time spans.
* Add `Fmt.truncated` to truncate your long strings.
* Add `Fmt.flush`, has the effect of `Format.pp_print_flush`.
* Add `Fmt.[Dump.]{field,record}` for records (#9).
* Add `Fmt.concat` to apply a list of formatters to a value.
* Add `Fmt.{semi,sps}`, separators.
* Add `Fmt.{error,error_msg}` to format `result` values.
* Add `Fmt.failwith_notrace`.
* Add `Fmt.( ++ )`, alias for `Fmt.append`.
* Add `Fmt.Dump.string`.
* Add more ANSI tty formatting styles and make them composable.
* Change `Fmt.{const,comma,cut,sp}`, generalize signature.
* Change `Fmt.append`, incompatible signature. Use `Fmt.(pair ~sep:nop)` if 
  you were using it (backward compatible with earlier versions of `Fmt`).
* Deprecate `Fmt.{strf,kstrf,strf_like}` in favor of `Fmt.{str,kstr,str_like}`.
* Deprecate `Fmt.{always,unit}` in favor of `Fmt.any`.
* Deprecate `Fmt.{prefix,suffix}` (specializes Fmt.( ++ )).
* Deprecate `Fmt.styled_unit`.
* No longer subvert the `Format` tag system to do dirty things.
  Thanks to David Kaloper Meršinjak for the work.

v0.8.6 2019-04-01 La Forclaz (VS)
---------------------------------

* Add `Fmt.{seq,Dump.seq}` to format `'a Seq.t` values. Thanks to
  Hezekiah M. Carty for the patch.
* Handle `Pervasives`'s deprecation via dependency on `stdlib-shims`.
* `Fmt.Dump.signal` format signals added in 4.03.
* Fix toplevel initialization for omod (#33).
* Require at least OCaml 4.03 (drops dependency on `result` and `uchar`
  compatibility packages).

v0.8.5 2017-12-27 La Forclaz (VS)
---------------------------------

* Fix `Fmt.{kstrf,strf_like}` when they are partially applied
  and repeatedly called. Thanks to Thomas Gazagnaire for the report.
* Add `Fmt.comma`.
* Relax the `Fmt.(invalid_arg, failwith)` type signature. Thanks to
  Hezekiah M. Carty for the patch.

v0.8.4 2017-07-08 Zagreb
------------------------

* Add `Fmt.{invalid_arg,failwith}`. Thanks to Hezekiah M. Carty for the patch.

v0.8.3 2017-04-13 La Forclaz (VS)
---------------------------------

* Fix `Fmt.exn_backtrace`. Thanks to Thomas Leonard for the report.

v0.8.2 2017-03-20 La Forclaz (VS)
---------------------------------

* Fix `META` file.

v0.8.1 2017-03-15 La Forclaz (VS)
---------------------------------

* `Fmt_tty.setup`, treat empty `TERM` env var as dumb.
* Add `Fmt.Dump.uchar` formatter for inspecting `Uchar.t` values.

v0.8.0 2016-05-23 La Forclaz (VS)
---------------------------------

* Build depend on topkg.
* Relicense from BSD3 to ISC.
* Tweak `Fmt.Dump.option` to indent like in sources.
* Add `Fmt.Dump.signal` formatter for `Sys` signal numbers.
* Add `Fmt[.Dump].result`, formatter for `result` values.
* Add `Fmt.{words,paragraphs}` formatters on US-ASCII strings.
* Add `Fmt.exn[_backtrace]`. Thanks to Edwin Török for suggesting.
* Add `Fmt.quote`.
* Rename `Fmt.text_range` to `Fmt.text_loc` and simplify output
  when range is a position.

v0.7.1 2015-12-03 Cambridge (UK)
--------------------------------

* Add optional esy_cmdliner support. See the `Fmt_cli` module provided
  by the package `fmt.cli`.

v0.7.0 2015-09-17 Cambridge (UK)
--------------------------------

First Release.
