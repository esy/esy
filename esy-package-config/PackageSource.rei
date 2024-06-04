/**

   [t] represents the entries in the lock files. That's why this
   module can be serialised to JSON.

 */
type t =
  | Link({
      path: DistPath.t,
      manifest: option(ManifestSpec.t),
      kind: Source.linkKind,
    })
  | Install({
      source: (Dist.t, list(Dist.t)),
      opam: option(opam),
    })
and opam = {
  name: OpamPackage.Name.t,
  version: OpamPackage.Version.t,
  path: Path.t,
};

let opam_to_yojson: Json.encoder(opam);
let opam_of_yojson: Json.decoder(opam);

let opamfiles: opam => RunAsync.t(list(File.t));

include S.JSONABLE with type t := t;
