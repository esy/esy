module Result = EsyLib.Result;
module Path = EsyLib.Path;
module OS = Bos.OS;

type registry = {
  registryPath: Path.t,
  overridePath: Path.t,
  remove: unit => Shared.result(unit),
};

type spec = {
  name: string,
  version: string,
  opam: string,
  url: option(string),
};

let repoFile =
  {|
  opam-version: "1.2"
  browse: "https://opam.ocaml.org/pkg/"
  upstream: "https://github.com/ocaml/opam-repository/tree/master/"
|}
  |> Shared.outdent;

let withPackages = name => {
  open Result.Syntax;
  let* root = Shared.getRandomTmpDir(~prefix=name, ());
  let* _ = OS.Dir.create(~path=true, Path.addSeg(root, "packages"));
  return(root);
};

let initialize = () => {
  open Result.Syntax;
  let* registryPath = withPackages("esy-opam-registry");
  let* overridePath = withPackages("esy-opam-override");

  let* _ = OS.File.write(Path.addSeg(registryPath, "repo"), repoFile);

  let remove = () => {
    let* _ = OS.Dir.delete(~recurse=true, registryPath);
    let* _ = OS.Dir.delete(~recurse=true, overridePath);
    return();
  };

  return({registryPath, overridePath, remove});
};

let defineOpamPackage = (registry, spec) => {
  open Result.Syntax;
  let packagePath =
    Path.(append(registry.registryPath, v("./packages/" ++ spec.name)));
  // let* _ = OS.Dir.create(~path=true, packagePath);
  let packageVersionPath =
    Path.addSeg(packagePath, spec.name ++ "." ++ spec.version);
  let* _ = OS.Dir.create(~path=true, packageVersionPath);
  // Put contents
  let* _ = OS.File.write(Path.addSeg(packageVersionPath, "opam"), spec.opam);
  let* _ =
    switch (spec.url) {
    | Some(url) => OS.File.write(Path.addSeg(packageVersionPath, "url"), url)
    | None => return()
    };
  return();
};
