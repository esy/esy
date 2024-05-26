/** This describes how a project should be built. */;
open DepSpec;
open EsyPackageConfig;
open EsyPrimitives;

type t =
  FetchDepsSubset.t = {
    all: FetchDepSpec.t,
    dev: FetchDepSpec.t,
  };

type mode =
  | Build
  | BuildDev;

let pp_mode: Fmt.t(mode);
let show_mode: mode => string;

let mode_to_yojson: Json.encoder(mode);
let mode_of_yojson: Json.decoder(mode);

let mode: (mode, EsyFetch.Package.t) => mode;
let depspec: (t, mode, EsyFetch.Package.t) => FetchDepSpec.t;
let buildCommands:
  (mode, EsyFetch.Package.t, BuildManifest.t) => BuildManifest.commands;
