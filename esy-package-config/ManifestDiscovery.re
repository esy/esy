let rec discover = (path, pkgName) => {
  open RunAsync.Syntax;
  let* fnames = Fs.listDir(path);
  let fnames = StringSet.of_list(fnames);
  let candidates = ref([]: list((ManifestSpec.kind, Path.t)));
  let* () =
    if (StringSet.mem("esy.json", fnames)) {
      candidates :=
        [(ManifestSpec.Esy, Path.(path / "esy.json")), ...candidates^];
      return();
    } else if (StringSet.mem("package.json", fnames)) {
      candidates :=
        [(ManifestSpec.Esy, Path.(path / "package.json")), ...candidates^];
      return();
    } else if (StringSet.mem("opam", fnames)) {
      let* isDir = Fs.isDir(Path.(path / "opam"));
      if (isDir) {
        let* opamFolderManifests = discover(Path.(path / "opam"), pkgName);
        candidates := List.concat([candidates^, opamFolderManifests]);
        return();
      } else {
        candidates :=
          [(ManifestSpec.Opam, Path.(path / "opam")), ...candidates^];
        return();
      };
    } else {
      let* filenames = {
        let f = filename => {
          let path = Path.(path / filename);
          if (Path.(hasExt(".opam", path))) {
            let* data = Fs.readFile(path);
            let opamPkgName /* without @opam/ prefix */ =
              switch (Astring.String.cut(~sep="/", pkgName)) {
              | Some(("@opam", n)) => n
              | _ => pkgName
              };
            return(
              opamPkgName
              ++ ".opam" == filename
              && String.(length(trim(data))) > 0,
            );
          } else {
            return(false);
          };
        };
        RunAsync.List.filter(~f, StringSet.elements(fnames));
      };
      switch (filenames) {
      | [] => return()
      | [filename] =>
        candidates :=
          [(ManifestSpec.Opam, Path.(path / filename)), ...candidates^];
        return();
      | filenames =>
        let opamFolderManifests =
          List.map(
            ~f=fn => (ManifestSpec.Opam, Path.(path / fn)),
            filenames,
          );
        candidates := List.concat([candidates^, opamFolderManifests]);
        return();
      };
    };
  return(candidates^);
};
