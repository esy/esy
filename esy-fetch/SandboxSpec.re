open EsyPackageConfig;

[@deriving (ord, yojson)]
type t = {
  path: Path.t,
  manifest,
}
and manifest =
  | Manifest(ManifestSpec.t)
  | ManifestAggregate(list(ManifestSpec.t));

let projectName = spec => {
  let nameOfPath = spec => Path.basename(spec.path);
  switch (spec.manifest) {
  | ManifestAggregate(_) => nameOfPath(spec)
  | [@implicit_arity] Manifest(Opam, "opam") => nameOfPath(spec)
  | [@implicit_arity] Manifest(Esy, "package.json")
  | [@implicit_arity] Manifest(Esy, "esy.json") => nameOfPath(spec)
  | [@implicit_arity] Manifest(_, fname) => Path.(show(remExt(v(fname))))
  };
};

let name = spec =>
  switch (spec.manifest) {
  | ManifestAggregate(_)
  | [@implicit_arity] Manifest(Opam, "opam")
  | [@implicit_arity] Manifest(Esy, "package.json")
  | [@implicit_arity] Manifest(Esy, "esy.json") => "default"
  | [@implicit_arity] Manifest(_, fname) => Path.(show(remExt(v(fname))))
  };

let isDefault = spec =>
  switch (spec.manifest) {
  | [@implicit_arity] Manifest(Esy, "package.json") => true
  | [@implicit_arity] Manifest(Esy, "esy.json") => true
  | _ => false
  };

let localPrefixPath = spec => {
  let name = name(spec);
  Path.(spec.path / "_esy" / name);
};

let manifestPath = spec =>
  switch (spec.manifest) {
  | Manifest((_kind, filename)) => Some(Path.(spec.path / filename))
  | ManifestAggregate(_) => None
  };

let manifestPaths = spec =>
  switch (spec.manifest) {
  | Manifest((_kind, filename)) => [Path.(spec.path / filename)]
  | ManifestAggregate(filenames) =>
    List.map(
      ~f=((_kind, filename)) => Path.(spec.path / filename),
      filenames,
    )
  };

let installationPath = spec =>
  Path.(localPrefixPath(spec) / "installation.json");
let pnpJsPath = spec => Path.(localPrefixPath(spec) / "pnp.js");
let cachePath = spec => Path.(localPrefixPath(spec) / "cache");
let storePath = spec => Path.(localPrefixPath(spec) / "store");
let buildPath = spec => Path.(localPrefixPath(spec) / "build");
let installPath = spec => Path.(localPrefixPath(spec) / "install");
let binPath = spec => Path.(localPrefixPath(spec) / "bin");
let distPath = spec => Path.(localPrefixPath(spec) / "dist");
let tempPath = spec => Path.(localPrefixPath(spec) / "tmp");

let solutionLockPath = spec =>
  switch (spec.manifest) {
  | ManifestAggregate(_)
  | [@implicit_arity] Manifest(Opam, "opam")
  | [@implicit_arity] Manifest(Esy, "package.json")
  | [@implicit_arity] Manifest(Esy, "esy.json") =>
    Path.(spec.path / "esy.lock")
  | _ => Path.(spec.path / (name(spec) ++ ".esy.lock"))
  };

let ofPath = path => {
  open RunAsync.Syntax;

  let discoverOfDir = path => {
    let* fnames = Fs.listDir(path);
    let fnames = StringSet.of_list(fnames);

    let* manifest =
      if (StringSet.mem("esy.json", fnames)) {
        return(Manifest((Esy, "esy.json")));
      } else if (StringSet.mem("package.json", fnames)) {
        return(Manifest((Esy, "package.json")));
      } else {
        let* hasOpam = {
          let has = StringSet.mem("opam", fnames);
          if (has) {
            let%map isDir = Fs.isDir(Path.(path / "opam"));
            !isDir;
          } else {
            return(false);
          };
        };
        if (hasOpam) {
          return(Manifest((Opam, "opam")));
        } else {
          let* filenames = {
            let f = filename => {
              let path = Path.(path / filename);
              if (Path.(hasExt(".opam", path))) {
                let* data = Fs.readFile(path);
                return(String.(length(trim(data))) > 0);
              } else {
                return(false);
              };
            };

            RunAsync.List.filter(~f, StringSet.elements(fnames));
          };

          switch (filenames) {
          | [] => errorf("no manifests found at %a", Path.pp, path)
          | [filename] => return(Manifest((Opam, filename)))
          | filenames =>
            let filenames =
              List.map(~f=fn => (ManifestSpec.Opam, fn), filenames);
            return(ManifestAggregate(filenames));
          };
        };
      };

    return({path, manifest});
  };

  let ofFile = path => {
    let sandboxPath = Path.(remEmptySeg(parent(path)));

    let rec tryLoad =
      fun
      | [] => errorf("cannot load sandbox manifest at: %a", Path.pp, path)
      | [fname, ...rest] => {
          let fpath = Path.(sandboxPath / fname);
          if%bind (Fs.exists(fpath)) {
            if (fname == "opam") {
              return({
                path: sandboxPath,
                manifest: [@implicit_arity] Manifest(Opam, fname),
              });
            } else {
              switch (Path.getExt(fpath)) {
              | ".json" =>
                return({
                  path: sandboxPath,
                  manifest: [@implicit_arity] Manifest(Esy, fname),
                })
              | ".opam" =>
                return({
                  path: sandboxPath,
                  manifest: [@implicit_arity] Manifest(Opam, fname),
                })
              | _ => tryLoad(rest)
              };
            };
          } else {
            tryLoad(rest);
          };
        };

    let fname = Path.basename(path);
    tryLoad([fname, fname ++ ".json", fname ++ ".opam"]);
  };

  if%bind (Fs.isDir(path)) {
    discoverOfDir(path);
  } else {
    ofFile(path);
  };
};

let pp = (fmt, spec) =>
  switch (spec.manifest) {
  | Manifest(filename) => ManifestSpec.pp(fmt, filename)
  | ManifestAggregate(filenames) =>
    Fmt.(list(~sep=any(", "), ManifestSpec.pp))(fmt, filenames)
  };

let show = spec => Format.asprintf("%a", pp, spec);

module Set =
  Set.Make({
    type nonrec t = t;
    let compare = compare;
  });

module Map =
  Map.Make({
    type nonrec t = t;
    let compare = compare;
  });
