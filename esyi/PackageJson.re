module Version = NpmVersion.Version;

module ExportedEnv = {
  type scope = [ | `Global | `Local];

  type item = {
    name: string,
    value: string,
    scope,
  };

  type t = list(item);

  let empty = [];

  let scope_to_yojson =
    fun
    | `Global => `String("global")
    | `Local => `String("local");

  let scope_of_yojson = (json: Json.t) : result(scope, string) =>
    Result.Syntax.(
      switch (json) {
      | `String("global") => return(`Global)
      | `String("local") => return(`Local)
      | _ => error("invalid scope value")
      }
    );

  let of_yojson = json =>
    Result.Syntax.(
      {
        let%bind items = Json.Parse.assoc(json);
        Result.List.map(
          ~f=
            ((name, v)) =>
              switch (v) {
              | `String(value) => return({name, value, scope: `Global})
              | `Assoc(_) =>
                let%bind value = Json.Parse.field(~name="val", v);
                let%bind value = Json.Parse.string(value);
                let%bind scope = Json.Parse.field(~name="scope", v);
                let%bind scope = scope_of_yojson(scope);
                return({name, value, scope});
              | _ => error("env value should be a string or an object")
              },
          items,
        );
      }
    );

  let to_yojson = (items: t) : Json.t => {
    let items =
      List.map(
        ~f=
          ({name, value, scope}) => (
            name,
            `Assoc([
              ("val", `String(value)),
              ("scope", scope_to_yojson(scope)),
            ]),
          ),
        items,
      );
    `Assoc(items);
  };
};

[@deriving of_yojson({strict: false})]
type t = {
  name: string,
  version: string,
  dependencies:
    [@default PackageInfo.Dependencies.empty] PackageInfo.Dependencies.t,
  devDependencies:
    [@default PackageInfo.Dependencies.empty] PackageInfo.Dependencies.t,
  peerDependencies:
    [@default PackageInfo.Dependencies.empty] PackageInfo.Dependencies.t,
  buildDependencies:
    [@default PackageInfo.Dependencies.empty] PackageInfo.Dependencies.t,
  dist: [@default None] option(dist),
}
and dist = {
  tarball: string,
  shasum: string,
};

let name = manifest => manifest.name;
let version = manifest => Version.parseExn(manifest.version);

let source = manifest =>
  switch (manifest.dist) {
  | Some(dist) =>
    Run.return(PackageInfo.Source.Archive(dist.tarball, dist.shasum))
  | None =>
    let msg =
      Printf.sprintf(
        "source cannot be found for %s@%s",
        manifest.name,
        manifest.version,
      );
    Run.error(msg);
  };

let dependencies = (manifest: t) => {
  PackageInfo.DependenciesInfo.dependencies: manifest.dependencies,
  buildDependencies: manifest.buildDependencies,
  devDependencies: manifest.devDependencies,
};

let ofFile = (path: Path.t) =>
  RunAsync.Syntax.(
    {
      let%bind data = Fs.readJsonFile(path);
      RunAsync.ofRun(Json.parseJsonWith(of_yojson, data));
    }
  );
