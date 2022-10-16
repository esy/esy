type t = list(OpamRegistry.t);

let make = (~cfg, ()) => {
  let opamRepositories = cfg.Config.opamRepositories;
  List.map(
    ~f=opamRepository => {OpamRegistry.make(~opamRepository, ~cfg, ())},
    opamRepositories,
  );
};
