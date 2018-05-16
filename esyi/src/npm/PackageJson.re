open Cudf;
open Shared;
open Types;

/*
 * Get dependencies data out of a package.json
 */

let getOpam = name => {
  let ln = 6;
  if (String.length(name) > ln && String.sub(name, 0, ln) == "@opam/") {
    Some(name)
    /* Some(String.sub(name, ln, String.length(name) - ln)) */
  } else {
    None
  }
};

let isGithub = value => {
  Str.string_match(Str.regexp("[a-zA-Z][a-zA-Z0-9-]+/[a-zA-Z0-9_-]+(#.+)?"), value, 0)
};

let startsWith = (value, needle) => String.length(value) > String.length(needle) && String.sub(value, 0, String.length(needle)) == needle;

let parseNpmSource = ((name, value)) => {
  switch (getOpam(name)) {
  | Some(name) => (name,
      switch (Shared.GithubVersion.parseGithubVersion(value)) {
      | Some(gh) => gh
      | None => Opam(
          OpamConcrete.parseNpmRange(value)
          /* NpmVersion.parseRange(value) |> GenericVersion.map(Shared.Types.opamFromNpmConcrete) */
        )
      }
      )
  | None => {
    (name,
      switch (Shared.GithubVersion.parseGithubVersion(value)) {
      | Some(gh) => gh
      | None => {
        if (startsWith(value, "git+")) {
          Git(value)
        } else {
          Npm(NpmVersion.parseRange(value))
        }

      }
      }
    )
  }
  }
};

let toDep = ((name, value)) => {
  let value = switch value {
  | `String(value) => value
  | _ => failwith("Unexpected dep value: " ++ Yojson.Basic.to_string(value))
  };

  parseNpmSource((name, value))
};

/**
 * Parse the deps
 *
 * - For each dep
 *   - grab the manifest (todo cache)
 *   - add all the matching packages to the universe
 *   - if a given version hasn't been added, then recursively process it
 * - how do I do this incrementally?
 * - or, how do I do it serially, but in a way that I can easily move to lwt?
 *
 */
let process = (parsed) => {
  /* TODO detect npm dependencies */
  switch parsed {
  | `Assoc(items) => {
    let dependencies = switch (List.assoc("dependencies", items)) {
    | exception Not_found => []
    | `Assoc(items) => items
    | _ => failwith("Unexpected value for dependencies")
    };
    let buildDependencies = switch (List.assoc("buildDependencies", items)) {
    | exception Not_found => []
    | `Assoc(items) => items
    | _ => failwith("Unexpected value for build deps")
    };
    let devDependencies = switch (List.assoc("devDependencies", items)) {
    | exception Not_found => []
    | `Assoc(items) => items
    | _ => failwith("Unexpected value for dev deps")
    };
    {
      Types.runtime: dependencies |> List.map(toDep),
      build: buildDependencies |> List.map(toDep),
      dev: devDependencies |> List.map(toDep),
      npm: []
    }
  }
  | _ => failwith("Invalid package.json")
  };
};

let getSource = (json) => {
  switch json {
  | `Assoc(items) => {
    switch (List.assoc("dist", items)) {
    | exception Not_found => {
      print_endline(Yojson.Basic.pretty_to_string(json));
      failwith("No dist")
    }

    | `Assoc(items) => {
      let archive = switch(List.assoc("tarball", items)) {
      | `String(archive) => archive
      | _ => failwith("Bad tarball")
      };
      let checksum = switch(List.assoc("shasum", items)) {
      | `String(checksum) => checksum
      | _ => failwith("Bad checksum")
      };
      Types.PendingSource.Archive(archive, Some(checksum))
    }
    | _ => failwith("bad dist")
    }
  }
  | _ => failwith("bad json manifest")
  }
};
