type t = {
  id : PackageId.t;
  name: string;
  version: Version.t;
  source: PackageSource.t;
  overrides: Overrides.t;
  dependencies : PackageId.Set.t;
  devDependencies : PackageId.Set.t;
}

let compare a b =
  PackageId.compare a.id b.id

let pp fmt pkg =
  Fmt.pf fmt "%s@%a" pkg.name Version.pp pkg.version

let show = Format.asprintf "%a" pp

let opam pkg =
  let open RunAsync.Syntax in
  match pkg.source with
  | Link _ -> return None
  | Install {opam = None; _} -> return None
  | Install {opam = Some opam; _} ->
    let name = OpamPackage.Name.to_string opam.name in
    let version = Version.Opam opam.version in
    let%bind opamfile =
      let path = Path.(opam.path / "opam") in
      let%bind data = Fs.readFile path in
      let filename = OpamFile.make (OpamFilename.of_string (Path.show path)) in
      try return (OpamFile.OPAM.read_from_string ~filename data) with
      | Failure msg -> errorf "error parsing opam metadata %a: %s" Path.pp path msg
      | _ -> error "error parsing opam metadata"
    in
    return (Some (name, version, opamfile))

module Map = Map.Make(struct type nonrec t = t let compare = compare end)
module Set = Set.Make(struct type nonrec t = t let compare = compare end)
