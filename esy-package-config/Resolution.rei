type t = {
  name: string,
  resolution,
}
and resolution =
  | Version(Version.t)
  | SourceOverride({
      source: Source.t,
      override: Json.t,
    });

let resolution_of_yojson: Json.decoder(resolution);
let resolution_to_yojson: Json.encoder(resolution);

let digest: t => Digestv.t;
let source: t => option(Source.t);

include S.COMPARABLE with type t := t;
include S.PRINTABLE with type t := t;
