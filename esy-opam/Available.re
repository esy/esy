let parseOpamFilterString = filterString => {
  let fakeManifest =
    Printf.sprintf(
      {|
         version: "1.1"
         opam-version: "2.0"
         available: %s
         |},
      filterString,
    );
  let opamFile = OpamFile.OPAM.read_from_string(fakeManifest);
  opamFile.available;
};

let evalAvailabilityFilter = (~os, ~arch, filter) => {
  let env = (var: OpamVariable.Full.t) => {
    let scope = OpamVariable.Full.scope(var);
    let name = OpamVariable.Full.variable(var);
    switch (scope, OpamVariable.to_string(name)) {
    | (OpamVariable.Full.Global, "arch") =>
      Some(OpamVariable.string(System.Arch.show(arch)))
    | (OpamVariable.Full.Global, "os") =>
      open System.Platform;
      // We could have avoided the following altogether if the System.Platform implementation
      // matched opam's. TODO
      let sys =
        switch (os) {
        | Darwin => "macos"
        | Linux => "linux"
        | Cygwin => "cygwin"
        | Unix => "unix"
        | Windows => "win32"
        | Unknown => "unknown"
        };
      Some(OpamVariable.string(sys));
    | (OpamVariable.Full.Global, _) => None
    | (OpamVariable.Full.Package(_), _) => None
    | (Self, _) => None
    };
  };

  OpamFilter.eval_to_bool(~default=true, env, filter);
};

let eval = (~os, ~arch, availabilityFilter) => {
  parseOpamFilterString(availabilityFilter)
  |> evalAvailabilityFilter(~os, ~arch);
};
