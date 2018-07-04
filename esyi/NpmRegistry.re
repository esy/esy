module Version = SemverVersion.Version;

module Packument = {
  module Versions = {
    type t = StringMap.t(Manifest.PackageJson.t);
    let of_yojson: Json.decoder(t) =
      Json.Parse.stringMap(Manifest.PackageJson.of_yojson);
  };

  [@deriving of_yojson({strict: false})]
  type t = {versions: Versions.t};
};

let rec retryInCaseOfError = (~num, ~desc, f) =>
  switch%lwt (f()) {
  | Ok(resp) => RunAsync.return(resp)
  | Error(_) when num > 0 =>
    let%lwt () =
      Logs_lwt.warn(m =>
        m("failed to %s, retrying (attempts left: %i)", desc, num)
      );
    retryInCaseOfError(~num=num - 1, ~desc, f);
  | Error(err) => Lwt.return(Error(err))
  };

let versions = (~cfg: Config.t, name) => {
  open RunAsync.Syntax;
  let desc = Format.asprintf("fetch %s", name);
  let name = Str.global_replace(Str.regexp("/"), "%2f", name);
  /* Some packages can be unpublished so we handle not found case by ignoring
   * it */
  switch%bind (
    retryInCaseOfError(~num=3, ~desc, () =>
      Curl.getOrNotFound(
        ~accept="application/vnd.npm.install-v1+json",
        cfg.npmRegistry ++ "/" ++ name,
      )
    )
  ) {
  | Curl.NotFound => return([])
  | Curl.Success(data) =>
    let%bind packument =
      RunAsync.ofRun(Json.parseStringWith(Packument.of_yojson, data));

    return(
      packument.Packument.versions
      |> StringMap.bindings
      |> List.map(~f=((version, packageJson)) => {
           let manifest = Manifest.ofPackageJson(packageJson);
           (SemverVersion.Version.parseExn(version), manifest);
         }),
    );
  };
};

let version = (~cfg: Config.t, name: string, version: Version.t) => {
  open RunAsync.Syntax;
  let desc = Format.asprintf("fetch %s@%a", name, Version.pp, version);
  let name = Str.global_replace(Str.regexp("/"), "%2f", name);
  let%bind data =
    retryInCaseOfError(~num=3, ~desc, () =>
      Curl.get(
        cfg.npmRegistry ++ "/" ++ name ++ "/" ++ Version.toString(version),
      )
    );
  let%bind packageJson =
    RunAsync.ofRun(
      Json.parseStringWith(Manifest.PackageJson.of_yojson, data),
    );
  let manifest = Manifest.ofPackageJson(packageJson);
  return(manifest);
};
