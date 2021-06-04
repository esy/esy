/**
 * This is a spec for a source, which at some point will be resolved to a
 * concrete source Source.t.
 */;

type t =
  | Archive({
      url: string,
      checksum: option(Checksum.t),
    })
  | Git({
      remote: string,
      ref: option(string),
      manifest: option(ManifestSpec.t),
    })
  | Github({
      user: string,
      repo: string,
      ref: option(string),
      manifest: option(ManifestSpec.t),
    })
  | LocalPath(Dist.local)
  | NoSource;

include S.PRINTABLE with type t := t;
include S.COMPARABLE with type t := t;

let to_yojson: t => [> | `String(string)];
let ofSource: Source.t => t;

let parser: Parse.t(t);
let parse: string => result(t, string);

module Map: Map.S with type key := t;
module Set: Set.S with type elt := t;
