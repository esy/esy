/*

  Task configuration.

  This represents platform-specific (a list of commands is specific to a
  platfoerm) but host-agnostic (do not have host specific absolute paths)
  package builds.

 */

module Env : {
  type t = Bos.OS.Env.t;
  let pp: Fmt.t(t);
  let of_yojson: EsyLib.Json.decoder(t);
  let to_yojson: EsyLib.Json.encoder(t);
};

type t = {
  id: string,
  name: string,
  version: string,
  sourceType: SourceType.t,
  buildType: BuildType.t,
  build: list(list(string)),
  install: list(list(string)),
  sourcePath: string,
  env: Env.t,
};

let of_yojson: EsyLib.Json.decoder(t);
let to_yojson: EsyLib.Json.encoder(t);
let ofFile: EsyLib.Path.t => Run.t(t, _);

