module Path = EsyLib.Path;

let filterNils = items =>
  items
  |> List.filter(x => x != None)
  |> List.map(item =>
       switch (item) {
       | Some(x) => x
       | None => assert(false)
       }
     );

let getFromOpamRegistry = (config, fullName) => {
  open RunAsync.Syntax;
  let name = OpamFile.withoutScope(fullName);
  let packagesPath =
    Path.(config.Config.opamRepositoryPath / "packages" / name);
  let%bind entries = Fs.listDir(packagesPath);
  return(
    List.map(
      entry => {
        let semver =
          switch (String.split_on_char('.', entry)) {
          | []
          | [_] => Types.Alpha("", None)
          | [_name, ...items] =>
            OpamVersion.parseConcrete(String.concat(".", items))
          };
        /* PERF: we should cache this, instead of re-parsing it later again */
        let manifest = {
          let path = Path.(packagesPath / entry / "opam" |> toString);
          OpamFile.parseManifest((name, semver), OpamParser.file(path));
        };
        if (! manifest.OpamFile.available) {
          None;
        } else {
          let opamFile = Path.(packagesPath / entry / "opam");
          let urlFile = Path.(packagesPath / entry / "url");
          let manifest = {
            OpamFile.ThinManifest.name,
            opamFile,
            urlFile,
            version: semver,
          };
          Some((semver, manifest));
        };
      },
      entries,
    )
    |> filterNils,
  );
};

let getManifest =
    (opamOverrides, {OpamFile.ThinManifest.opamFile, urlFile, name, version}) =>
  RunAsync.Syntax.(
    {
      let%bind source =
        if%bind (Fs.exists(urlFile)) {
          return(
            OpamFile.parseUrlFile(OpamParser.file(Path.toString(urlFile))),
          );
        } else {
          return(Types.PendingSource.NoSource);
        };
      let manifest = {
        ...
          OpamFile.parseManifest(
            (name, version),
            OpamParser.file(Path.toString(opamFile)),
          ),
        source,
      };
      switch%bind (
        OpamOverrides.findApplicableOverride(opamOverrides, name, version)
      ) {
      | None =>
        /* print_endline("No override for " ++ name ++ " " ++ VersionNumber.viewVersionNumber(version)); */
        return(manifest)
      | Some(override) =>
        /* print_endline("!! Found override for " ++ name); */
        let m = OpamOverrides.applyOverride(manifest, override);
        return(m);
      };
    }
  );
