[@deriving ord]
type available = (System.Platform.t, System.Arch.t);

module Set =
  Set.Make({
    [@deriving ord]
    type t = available;
  });

type t = Set.t;

let of_yojson =
  fun
  | `List(availablePlatforms) => {
      let f = acc => (
        fun
        | `List([`String(os), `String(arch)]) as json =>
          switch (acc, System.Platform.parse(os), System.Arch.parse(arch)) {
          | (Ok(acc), Ok(os), arch) => Ok(Set.add((os, arch), acc))
          | _ =>
            Result.errorf(
              "AvailablePlatforms.parse couldn't parse: %a",
              Json.Print.ppRegular,
              json,
            )
          }
        | json =>
          Result.errorf(
            "AvailablePlatforms.parse couldn't parse: %a",
            Json.Print.ppRegular,
            json,
          )
      );
      List.fold_left(~f, ~init=Ok(Set.empty), availablePlatforms);
    }
  | json =>
    Result.errorf(
      "Unexpected JSON %a where AvailablePlatforms.t was expected",
      Json.Print.ppRegular,
      json,
    );

let to_yojson = platforms => {
  let f = ((os, arch)) =>
    `List([System.Platform.to_yojson(os), System.Arch.to_yojson(arch)]);
  `List(platforms |> Set.elements |> List.map(~f));
};

let default: t =
  Set.of_list([
    (System.Platform.Windows, System.Arch.X86_64),
    (System.Platform.Linux, System.Arch.X86_64),
    (System.Platform.Darwin, System.Arch.X86_64),
    (System.Platform.Darwin, System.Arch.Arm64),
  ]);

let filter = (availabilityFilter, platforms) => {
  let f = ((os, arch)) => {
    Available.evalAvailabilityFilter(~os, ~arch, availabilityFilter);
  };
  Set.filter(f, platforms);
};

let missing = (~expected, ~actual) => Set.diff(expected, actual);

let isEmpty = v => Set.is_empty(v);
let empty = Set.empty;
let add = (~os, ~arch, v) => Set.add((os, arch), v);
let toList = Set.elements;

let ppEntry = (ppf, (os, arch)) =>
  Fmt.pf(ppf, "%a %a", System.Platform.pp, os, System.Arch.pp, arch);

let pp = (ppf, v) => {
  let sep = Fmt.any(", ");
  Fmt.hbox(Fmt.list(~sep, ppEntry), ppf, Set.elements(v));
};

let union = (a, b) => Set.union(a, b);

module Map = {
  include Map.Make({
    type t = available;
    let compare = compare;
  });

  let to_yojson = (v_to_yojson, map) => {
    let items = {
      let f = (k, v, items) => {
        let (os, arch) = k;
        let k =
          Format.asprintf(
            "%a+%a",
            System.Platform.pp,
            os,
            System.Arch.pp,
            arch,
          );
        [(k, v_to_yojson(v)), ...items];
      };

      fold(f, map, []);
    };

    `Assoc(items);
  };

  let of_yojson = v_of_yojson =>
    Result.Syntax.(
      fun
      | `Assoc(items) => {
          let f = (map, (k, v)) => {
            let* (os, arch) =
              switch (String.split_on_char('+', k)) {
              | [os, arch] =>
                switch (System.Platform.parse(os), System.Arch.parse(arch)) {
                | (Ok(os), arch) => Ok((os, arch))
                | _ =>
                  Result.errorf("Couldn't parse %s into os-arch tuple", k)
                }
              | _ => errorf("Expect key %s to be of syntax <os>+<arch>", k)
              };
            let* v = v_of_yojson(v);
            return(add((os, arch), v, map));
          };

          Result.List.foldLeft(~f, ~init=empty, items);
        }
      | _ => error("expected an object")
    );
};
