module File = {
  module Cache =
    Memoize.Make({
      type key = Path.t;
      type value = RunAsync.t(OpamFile.OPAM.t);
    });

  let ofString = (~upgradeIfOpamVersionIsLessThan=?, ~filename=?, data) => {
    let filename = {
      let filename = Option.orDefault(~default="opam", filename);
      OpamFile.make(OpamFilename.of_string(filename));
    };

    let opam = OpamFile.OPAM.read_from_string(~filename, data);
    switch (upgradeIfOpamVersionIsLessThan) {
    | Some(upgradeIfOpamVersionIsLessThan) =>
      let opamVersion = OpamFile.OPAM.opam_version(opam);
      if (OpamVersion.compare(opamVersion, upgradeIfOpamVersionIsLessThan) < 0) {
        OpamFormatUpgrade.opam_file(~filename, opam);
      } else {
        opam;
      };
    | None => opam
    };
  };

  let ofPath = (~upgradeIfOpamVersionIsLessThan=?, ~cache=?, path) => {
    open RunAsync.Syntax;
    let load = () => {
      let* data = Fs.readFile(path);
      let filename = Path.show(path);
      return(ofString(~upgradeIfOpamVersionIsLessThan?, ~filename, data));
    };

    switch (cache) {
    | Some(cache) => Cache.compute(cache, path, load)
    | None => load()
    };
  };
};

type t = {
  name: OpamPackage.Name.t,
  version: OpamPackage.Version.t,
  opam: OpamFile.OPAM.t,
  url: option(OpamFile.URL.t),
  override: option(Override.t),
  opamRepositoryPath: option(Path.t),
};

let ofPath = (~name, ~version, path: Path.t) => {
  open RunAsync.Syntax;
  let* opam = File.ofPath(path);
  return({
    name,
    version,
    opamRepositoryPath: Some(Path.parent(path)),
    opam,
    override: None,
    url: None,
  });
};

let ofString = (~name, ~version, data: string) => {
  open Run.Syntax;
  let opam = File.ofString(data);
  return({
    name,
    version,
    opam,
    url: None,
    override: None,
    opamRepositoryPath: None,
  });
};
