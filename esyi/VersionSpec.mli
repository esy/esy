(**
 * This representes a concrete version which at some point will be resolved to a
 * concrete version Version.t.
 *)

include module type of Types.VersionSpec

val pp : t Fmt.t
val toString : t -> string
val to_yojson : t -> [> `String of string ]

include S.COMPARABLE with type t := t

val parserNpm : t Parse.t
val parserOpam : t Parse.t

val matches : version:Version.t -> t -> bool
val ofVersion : Version.t -> t
