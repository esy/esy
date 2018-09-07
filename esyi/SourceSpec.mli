(**
 * This is a spec for a source, which at some point will be resolved to a
 * concrete source Source.t.
 *)

type t =
  | Archive of {
      url : string;
      checksum : Checksum.t option;
    }
  | Git of {
      remote : string;
      ref : string option;
      manifest : string option;
    }
  | Github of {
      user : string;
      repo : string;
      ref : string option;
      manifest : string option;
    }
  | LocalPath of {
      path : Path.t;
      manifest : string option;
    }
  | LocalPathLink of {
      path : Path.t;
      manifest : string option;
    }
  | NoSource

val toString : t -> string
val to_yojson : t -> [> `String of string ]
val pp : t Fmt.t
val ofSource : Source.t -> t
val equal : t -> t -> bool
val compare : t -> t -> int
val matches : source:Source.t -> t -> bool

val parser : t Parse.t
val parse : string -> (t, string) result

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
