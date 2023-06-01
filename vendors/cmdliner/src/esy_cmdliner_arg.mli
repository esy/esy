(*---------------------------------------------------------------------------
   Copyright (c) 2011 Daniel C. Bünzli. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   %%NAME%% %%VERSION%%
  ---------------------------------------------------------------------------*)

(** Command line arguments as terms. *)

type 'a parser = string -> [ `Ok of 'a | `Error of string ]
type 'a printer = Format.formatter -> 'a -> unit
type 'a conv = 'a parser * 'a printer
type 'a converter = 'a conv

val conv :
  ?docv:string -> (string -> ('a, [`Msg of string]) result) * 'a printer ->
  'a conv

val pconv : ?docv:string -> 'a parser * 'a printer -> 'a conv
val conv_parser : 'a conv -> (string -> ('a, [`Msg of string]) result)
val conv_printer : 'a conv -> 'a printer
val conv_docv : 'a conv -> string

val parser_of_kind_of_string :
  kind:string -> (string -> 'a option) ->
  (string -> ('a, [`Msg of string]) result)

val some : ?none:string -> 'a converter -> 'a option converter

type env = Esy_cmdliner_info.env
val env_var : ?docs:string -> ?doc:string -> string -> env

type 'a t = 'a Esy_cmdliner_term.t

type info
val info :
  ?docs:string -> ?docv:string -> ?doc:string -> ?env:env -> string list -> info

val ( & ) : ('a -> 'b) -> 'a -> 'b

val flag : info -> bool t
val flag_all : info -> bool list t
val vflag : 'a -> ('a * info) list -> 'a t
val vflag_all : 'a list -> ('a * info) list -> 'a list t
val opt : ?vopt:'a -> 'a converter -> 'a -> info -> 'a t
val opt_all : ?vopt:'a -> 'a converter -> 'a list -> info -> 'a list t

val pos : ?rev:bool -> int -> 'a converter -> 'a -> info -> 'a t
val pos_all : 'a converter -> 'a list -> info -> 'a list t
val pos_left : ?rev:bool -> int -> 'a converter -> 'a list -> info -> 'a list t
val pos_right : ?rev:bool -> int -> 'a converter -> 'a list -> info -> 'a list t

(** {1 As terms} *)

val value : 'a t -> 'a Esy_cmdliner_term.t
val required : 'a option t -> 'a Esy_cmdliner_term.t
val non_empty : 'a list t -> 'a list Esy_cmdliner_term.t
val last : 'a list t -> 'a Esy_cmdliner_term.t

(** {1 Predefined arguments} *)

val man_format : Esy_cmdliner_manpage.format Esy_cmdliner_term.t
val stdopt_version : docs:string -> bool Esy_cmdliner_term.t
val stdopt_help : docs:string -> Esy_cmdliner_manpage.format option Esy_cmdliner_term.t

(** {1 Converters} *)

val bool : bool converter
val char : char converter
val int : int converter
val nativeint : nativeint converter
val int32 : int32 converter
val int64 : int64 converter
val float : float converter
val string : string converter
val enum : (string * 'a) list -> 'a converter
val file : string converter
val dir : string converter
val non_dir_file : string converter
val list : ?sep:char -> 'a converter -> 'a list converter
val array : ?sep:char -> 'a converter -> 'a array converter
val pair : ?sep:char -> 'a converter -> 'b converter -> ('a * 'b) converter
val t2 : ?sep:char -> 'a converter -> 'b converter -> ('a * 'b) converter

val t3 :
  ?sep:char -> 'a converter ->'b converter -> 'c converter ->
  ('a * 'b * 'c) converter

val t4 :
  ?sep:char -> 'a converter ->'b converter -> 'c converter -> 'd converter ->
  ('a * 'b * 'c * 'd) converter

val doc_quote : string -> string
val doc_alts : ?quoted:bool -> string list -> string
val doc_alts_enum : ?quoted:bool -> (string * 'a) list -> string


(*---------------------------------------------------------------------------
   Copyright (c) 2011 Daniel C. Bünzli

   Permission to use, copy, modify, and/or distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
  ---------------------------------------------------------------------------*)
