module Path = EsyLib.Path;
module Config = Shared.Config;

module Api = {
  let (/+) = Filename.concat;

  let solve = (config: Config.t) => {
    let json =
      Yojson.Basic.from_file(
        Path.(config.basePath / "package.json" |> to_string),
      );
    let env = Solve.solve(config, `PackageJson(json));
    let json = Shared.Env.to_yojson(Shared.Types.Source.to_yojson, env);
    let chan =
      open_out(Path.(config.basePath / "esyi.lock.json" |> to_string));
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
};

module CommandLineInterface = {
  open Cmdliner;

  let exits = Term.default_exits;
  let sdocs = Manpage.s_common_options;

  let basedir = Sys.getcwd();
  let version = "0.1.0";

  let defaultCommand = {
    let doc = "Dependency installer";
    let info = Term.info("esyi", ~version, ~doc, ~sdocs, ~exits);
    let cmd = () => {
      print_endline("s");
      print_endline(basedir);
      let config = Shared.Config.make(Path.v(basedir));
      Api.solve(config);
      Api.fetch(config);
      `Ok();
    };
    (Term.(ret(const(cmd) $ const())), info);
  };

  let solveCommand = {
    let doc = "Solve dependencies and store the solution as a lockfile";
    let info = Term.info("solve", ~version, ~doc, ~sdocs, ~exits);
    let cmd = () => {
      let config = Shared.Config.make(Path.v(basedir));
      Api.solve(config);
      `Ok();
    };
    (Term.(ret(const(cmd) $ const())), info);
  };

  let fetchCommand = {
    let doc = "Fetch dependencies using the solution in a lockfile";
    let info = Term.info("fetch", ~version, ~doc, ~sdocs, ~exits);
    let cmd = () => {
      let config = Shared.Config.make(Path.v(basedir));
      Api.fetch(config);
      `Ok();
    };
    (Term.(ret(const(cmd) $ const())), info);
  };

  let commands = [solveCommand, fetchCommand];

  let run = () => {
    Printexc.record_backtrace(true);
    Term.(exit(eval_choice(~argv=Sys.argv, defaultCommand, commands)));
  };
};

let () = CommandLineInterface.run();
