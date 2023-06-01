type t = list(Override.t);

let empty = [];

let isEmpty =
  fun
  | [] => true
  | _ => false;

let add = (override, overrides) => [override, ...overrides];

let addMany = (newOverrides, overrides) => newOverrides @ overrides;

let merge = (newOverrides, overrides) => newOverrides @ overrides;

let fold' = (~f, ~init, overrides) =>
  RunAsync.List.foldLeft(~f, ~init, List.rev(overrides));

let foldWithBuildOverrides = (~f, ~init, overrides) => {
  open RunAsync.Syntax;
  let f = (v, override) => {
    let%lwt () =
      Esy_logs_lwt.debug(m => m("build override: %a", Override.pp, override));
    switch%bind (Override.build(override)) {
    | Some(override) => return(f(v, override))
    | None => return(v)
    };
  };

  fold'(~f, ~init, overrides);
};

let foldWithInstallOverrides = (~f, ~init, overrides) => {
  open RunAsync.Syntax;
  let f = (v, override) => {
    let%lwt () =
      Esy_logs_lwt.debug(m =>
        m("install override: %a", Override.pp, override)
      );
    switch%bind (Override.install(override)) {
    | Some(override) => return(f(v, override))
    | None => return(v)
    };
  };

  fold'(~f, ~init, overrides);
};
