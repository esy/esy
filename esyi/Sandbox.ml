type t = {
  cfg : Config.t;
  path : Path.t;
  resolutions : Manifest.Resolutions.t;
  root : Package.t;
}

module EsyManifest = struct
  module ParseResolutions = struct
    type t = {
      resolutions : (Package.Resolutions.t [@default Package.Resolutions.empty]);
    } [@@deriving of_yojson { strict = false }]
  end

  let ofDir (path : Path.t) =
    let open RunAsync.Syntax in
    match%bind Manifest.find path with
    | Some filename ->
      let%bind json = Fs.readJsonFile filename in
      let%bind pkgJson = RunAsync.ofRun (Json.parseJsonWith Manifest.PackageJson.of_yojson json) in
      let%bind resolutions = RunAsync.ofRun (Json.parseJsonWith ParseResolutions.of_yojson json) in
      let manifest = Manifest.ofPackageJson pkgJson in
      let%bind pkg = 
        let version = Package.Version.Source (Package.Source.LocalPath path) in
        Manifest.toPackage ~version manifest
      in
      return (Some (pkg, resolutions.ParseResolutions.resolutions))
    | None -> return None
end

module OpamManifest = struct
  let ofDir (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind filenames = Fs.listDir path in
    let%bind opams =
      let version = OpamPackage.Version.of_string "dev" in
      filenames
      |> List.map ~f:(fun name -> Path.(path / name))
      |> List.filter ~f:(fun path ->
          Path.has_ext ".opam" path || Path.basename path = "opam")
      |> List.map ~f:(fun path ->
          let name =
            let name = Path.(path |> rem_ext |> basename) in
            OpamPackage.Name.of_string name in
          OpamRegistry.Manifest.ofFile ~name ~version path)
      |> RunAsync.List.joinAll
    in
    match opams with
    | [] -> return None
    | opams ->
      let%bind pkgs =
        let version = Package.Version.Source (Package.Source.LocalPath path) in
        let f opam = OpamRegistry.Manifest.toPackage ~name:"root" ~version opam in
        RunAsync.List.joinAll (List.map ~f opams)
      in
      let dependencies, devDependencies =
        let f (dependencies, devDependencies) (pkg : Package.t) =
          match pkg.dependencies, pkg.devDependencies with
          | Package.Dependencies.OpamFormula du, Package.Dependencies.OpamFormula ddu ->
            du @ dependencies, ddu @ devDependencies
          | _ -> assert false
        in
        List.fold_left ~f ~init:([], []) pkgs
      in
      return (Some {
        Package.
        name = "root";
        version = Package.Version.Source (Package.Source.LocalPath path);
        source = Package.Source (Package.Source.LocalPath path), [];
        dependencies = Package.Dependencies.OpamFormula dependencies;
        devDependencies = Package.Dependencies.OpamFormula devDependencies;
        opam = None;
        kind = Package.Esy;
      })
end

let ofDir ~cfg (path : Path.t) =
  let open RunAsync.Syntax in
  match%bind EsyManifest.ofDir path with
  | Some (root, resolutions) -> return {cfg; path; root; resolutions}
  | None ->
    begin match%bind OpamManifest.ofDir path with
    | Some root -> return {cfg; path; root; resolutions = Manifest.Resolutions.empty}
    | None -> error "unable to find either package.json or opam files"
    end
