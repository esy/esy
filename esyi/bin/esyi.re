module Path = EsyLib.Path;

let (/+) = Filename.concat;

let solve = (config, basedir) => {
  let json = Yojson.Basic.from_file(basedir /+ "package.json");
  let env = Solve.solve(config, `PackageJson(json));
  let json = Shared.Env.to_yojson(Shared.Types.Source.to_yojson, env);
  let chan = open_out(basedir /+ "esyi.lock.json");
  Yojson.Safe.pretty_to_channel(chan, json);
  close_out(chan);
};

let fetch = (config, basedir) => {
  let json = Yojson.Safe.from_file(basedir /+ "esyi.lock.json");
  let env =
    switch (Shared.Env.of_yojson(Shared.Types.Source.of_yojson, json)) {
    | Error(_a) => failwith("Bad lockfile")
    | Ok(a) => a
    };
  Shared.Files.removeDeep(basedir /+ "node_modules");
  Fetch.fetch(config, basedir, env);
};

Printexc.record_backtrace(true);

switch (Sys.argv) {
| [|_, "solve", basedir|] =>
  let config = Shared.Config.make(Path.v(basedir));
  solve(config, basedir);
| [|_, "fetch", basedir|] =>
  let config = Shared.Config.make(Path.v(basedir));
  fetch(config, basedir);
| [|_, basedir|] =>
  let config = Shared.Config.make(Path.v(basedir));
  solve(config, basedir);
  fetch(config, basedir);
| _ => print_endline("Usage: esyi basedir")
};
