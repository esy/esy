
open Shared.Infix;

/* TODO use lwt, maybe cache things */

let getFromNpmRegistry = name => {
  let name = Str.global_replace(Str.regexp("/"), "%2f", name);
  let json = Shared.Wget.get("http://registry.npmjs.org/" ++ name) |! "Unable to query registry for " ++ name |> Yojson.Basic.from_string;
  switch json {
  | `Assoc(items) => {
    switch (List.assoc("versions", items)) {
    | exception Not_found => {
      print_endline(Yojson.Basic.to_string(json));
      failwith("No versions field in the registry result for " ++ name)
    }
    | `Assoc(items) => {
      List.map(
        ((name, json)) => (NpmVersion.parseConcrete(name), json),
        items
      )
    }
    | _ => failwith("Invalid versions field for registry response to " ++ name)
    }
  }
  | _ => failwith("Invalid registry response for " ++ name)
  }
};
