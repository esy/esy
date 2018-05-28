open EsyLib;

/* TODO use lwt, maybe cache things */
let getFromNpmRegistry = (config: Shared.Config.t, name) => {
  open RunAsync.Syntax;
  let name = Str.global_replace(Str.regexp("/"), "%2f", name);
  let%bind json = Shared.Wget.get(config.npmRegistry ++ "/" ++ name);
  let json = Yojson.Basic.from_string(json);
  switch (json) {
  | `Assoc(items) =>
    switch (List.assoc("versions", items)) {
    | exception Not_found =>
      print_endline(Yojson.Basic.to_string(json));
      failwith("No versions field in the registry result for " ++ name);
    | `Assoc(items) =>
      return(
        List.map(
          ((name, json)) => (NpmVersion.parseConcrete(name), json),
          items,
        ),
      )
    | _ =>
      failwith("Invalid versions field for registry response to " ++ name)
    }
  | _ => failwith("Invalid registry response for " ++ name)
  };
};
