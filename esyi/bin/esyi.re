module Path = EsyLib.Path;
module Config = Shared.Config;

let (/+) = Filename.concat;

let solve = (config: Config.t) => {
  let json =
    Yojson.Basic.from_file(
      Path.(config.basePath / "package.json" |> to_string),
    );
  let env = Solve.solve(config, `PackageJson(json));
  let json = Shared.Env.to_yojson(Shared.Types.Source.to_yojson, env);
  let chan = open_out(Path.(config.basePath / "esyi.lock.json" |> to_string));
  Yojson.Safe.pretty_to_channel(chan, json);
  close_out(chan);
};

let fetch = (config: Config.t) => {
  let json =
    Yojson.Safe.from_file(
      Path.(config.basePath / "esyi.lock.json" |> to_string),
    );
  let env =
    switch (Shared.Env.of_yojson(Shared.Types.Source.of_yojson, json)) {
    | Error(_a) => failwith("Bad lockfile")
    | Ok(a) => a
    };
  Shared.Files.removeDeep(
    Path.(config.basePath / "node_modules" |> to_string),
  );
  Fetch.fetch(config, env);
};

Printexc.record_backtrace(true);

switch (Sys.argv) {
| [|_, "solve", basedir|] =>
  let config = Shared.Config.make(Path.v(basedir));
  solve(config);
| [|_, "fetch", basedir|] =>
  let config = Shared.Config.make(Path.v(basedir));
  fetch(config);
| [|_, basedir|] =>
  let config = Shared.Config.make(Path.v(basedir));
  solve(config);
  fetch(config);
| _ => print_endline("Usage: esyi basedir")
};
