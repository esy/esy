open EsyPackageConfig;

type t = {
  id: PackageId.t,
  name: string,
  version: Version.t,
  source: PackageSource.t,
  overrides: Overrides.t,
  dependencies: PackageId.Set.t,
  devDependencies: PackageId.Set.t,
};

let compare = (a, b) => PackageId.compare(a.id, b.id);

let pp = (fmt, pkg) =>
  Fmt.pf(fmt, "%s@%a", pkg.name, Version.pp, pkg.version);

let show = Format.asprintf("%a", pp);

let id = pkg => pkg.id;

let opam = pkg =>
  RunAsync.Syntax.(
    switch (pkg.source) {
    | Link(_) => return(None)
    | Install({opam: None, _}) => return(None)
    | Install({opam: Some(opam), _}) =>
      let name = OpamPackage.Name.to_string(opam.name);
      let version = Version.Opam(opam.version);
      let%bind opamfile = {
        let path = Path.(opam.path / "opam");
        let%bind data = Fs.readFile(path);
        let filename =
          OpamFile.make(OpamFilename.of_string(Path.show(path)));
        try (return(OpamFile.OPAM.read_from_string(~filename, data))) {
        | Failure(msg) =>
          errorf("error parsing opam metadata %a: %s", Path.pp, path, msg)
        | _ => error("error parsing opam metadata")
        };
      };

      return(Some((name, version, opamfile)));
    }
  );

module Map =
  Map.Make({
    type nonrec t = t;
    let compare = compare;
  });
module Set =
  Set.Make({
    type nonrec t = t;
    let compare = compare;
  });
