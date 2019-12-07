module Path = EsyLib.Path;
module Option = EsyLib.Option;
module Result = EsyLib.Result;
module System = EsyLib.System;
module Dir = Bos.OS.Dir;
module File = Bos.OS.File;
module BPath = Bos.OS.Path;

type t =
  | FixtureSymlink({
      name: string,
      path: string,
    })
  | FixtureFileCopy({
      name: string,
      path: string,
    })
  | FixtureFile({
      name: string,
      data: string,
    })
  | FixtureDir({
      name: string,
      items: list(t),
    });

let transfer = (ic, oc, ()) => {
  let chunkSize = 1024 * 1024; /* 1mb */
  let buffer = Bytes.create(chunkSize);
  let rec loop = () => {
    switch (input(ic, buffer, 0, chunkSize)) {
    | 0 => Result.return()
    | n =>
      output(oc, buffer, 0, n);
      loop();
    };
  };
  loop();
};

let copyFile = (iFile, oFile) => {
  let result =
    File.with_ic(
      iFile,
      (ic, ()) => File.with_oc(oFile, transfer(ic), ()),
      (),
    );
  /**
    Joining the result here, to unwrap layer
    with_oc -> ((result, error), error)
    with_ic -> (((result, error), error), error)
    We are 3 layers deep
   */
  result
  |> Result.join
  |> Result.join;
};

let rec layout = p =>
  fun
  | FixtureSymlink({name, path}) =>
    BPath.symlink(~target=Path.v(path), Path.addSeg(p, name))
  | FixtureFileCopy(spec) =>
    copyFile(Path.v(spec.path), Path.addSeg(p, spec.name))
  | FixtureFile(spec) => File.write(Path.addSeg(p, spec.name), spec.data)
  | FixtureDir(spec) => {
      open Result.Syntax;
      let newPath = Path.addSeg(p, spec.name);
      let%bind _ = Dir.create(newPath);
      layoutMany(newPath, spec.items);
    }
and layoutMany = p =>
  fun
  | [] => Result.return()
  | [item, ...rest] => {
      switch (layout(p, item)) {
      | Ok(_) => layoutMany(p, rest)
      | Error(e) => Result.error(e)
      };
    };

let packageJson = entry => {
  FixtureFile({name: "package.json", data: PackageJson.toString(entry)});
};

let defaultProject = () => {
  packageJson(PackageJson.make(~name="esy", ~version="1.0.0", ()));
};
