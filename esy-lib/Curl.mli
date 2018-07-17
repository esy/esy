(**
 * Work with remote URLs via curl utility.
 *)

type response =
  | Success of string
  | NotFound

type headers = string StringMap.t

type url = string

val getOrNotFound :
  ?accept : string
  -> url
  -> response RunAsync.t

(** Return map of headers for the urls, all header names are lowercased *)
val head :
  url
  -> headers RunAsync.t

val get :
  ?accept : string
  -> url
  -> string RunAsync.t

val download :
  output:Fpath.t
  -> url
  -> unit RunAsync.t
