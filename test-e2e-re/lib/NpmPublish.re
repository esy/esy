open EsyPackageConfig;

module Result = EsyLib.Result;
module Path = EsyLib.Path;
module OS = Bos.OS;
module Cmd = Bos.Cmd;

[@deriving (ord, of_yojson({strict: false}), to_yojson)]
type t = {
  name: string,
  version: Version.t,
};

let toString = data => {
  data |> to_yojson |> Yojson.Safe.to_string;
};

let make = (~name, ~version, ()) => {
  {
    name,
    version: Version.parseExn(version),
  };
};
/* When using npm, i've seemed to hit quite few issues */
let npmPublish = Cmd.(v("yarn") % "publish");
let flags = Cmd.(v("--non-interactive"));
let putRc = (path, registry) => {
  let token = Printf.sprintf("%s/:_authToken=\"fooBar\"", registry);
  let rcPath = Path.addSeg(path, ".npmrc");
  OS.File.write(rcPath, token);
};

/*
 Makes a new directory
 Inserts package.json
 Creates .npmrc to fake auth (maybe there is a better method?)
 Runs publish in directory
 Deletes directory
 */
let publish = (package, registry) => {
  open Result.Syntax;
  let* root = Shared.getRandomTmpDir(~prefix="esy-publish-", ());
  let* _ = OS.Dir.create(root);

  let fixture =
    Fixture.FixtureFile({
      name: "package.json",
      data: toString(package),
    });
  let* () = Fixture.layout(root, fixture);
  let* () = putRc(root, registry);

  let program = Cmd.(npmPublish % "--registry" % registry %% flags);
  let revert = Shared.changeCwd(Path.show(root));
  /* Do not bind here to make sure cleanup gets executed */
  let result = OS.Cmd.(run_out(~err=err_null, program) |> to_null);
  revert();
  let* () = OS.Dir.delete(~must_exist=true, ~recurse=true, root);
  result;
};
