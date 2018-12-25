open EsyPackageConfig

module Dependencies = Package.Dependencies

module CudfName : sig

  type t

  val make : string -> t
  val encode : string -> t
  val decode : t -> string
  val show : t -> string
  val pp : t Fmt.t

end = struct
  type t = string

  let escapeWith = "UuU"
  let underscoreRe = Re.(compile (char '_'))
  let underscoreEscapeRe = Re.(compile (str escapeWith))

  let make name = name
  let encode name = Re.replace_string underscoreRe ~by:escapeWith name
  let decode name = Re.replace_string underscoreEscapeRe ~by:"_" name
  let show name = name
  let pp = Fmt.string
end

type t = {
  pkgs : Package.t Version.Map.t StringMap.t;
  resolver : Resolver.t;
}

type univ = t

let empty resolver = {
  pkgs = StringMap.empty;
  resolver;
}

let add ~pkg (univ : t) =
  let {Package. name; version; _} = pkg in
  let versions =
    match StringMap.find_opt name univ.pkgs with
    | None -> Version.Map.empty
    | Some versions -> versions
  in
  let pkgs = StringMap.add name (Version.Map.add version pkg versions) univ.pkgs in
  {univ with pkgs}

let mem ~pkg (univ : t) =
  match StringMap.find pkg.Package.name univ.pkgs with
  | None -> false
  | Some versions -> Version.Map.mem pkg.Package.version versions

let findVersion ~name ~version (univ : t) =
  match StringMap.find name univ.pkgs with
  | None -> None
  | Some versions -> Version.Map.find_opt version versions

let findVersionExn ~name ~version (univ : t) =
  match findVersion ~name ~version univ with
  | Some pkg -> pkg
  | None ->
    let msg =
      Printf.sprintf
        "inconsistent state: package not in the universr %s@%s"
        name (Version.show version)
    in
    failwith msg

let findVersions ~name (univ : t) =
  match StringMap.find name univ.pkgs with
  | None -> []
  | Some versions ->
    versions
    |> Version.Map.bindings
    |> List.map ~f:(fun (_, pkg) -> pkg)

module CudfVersionMap : sig
  type t

  val make : ?size:int -> unit -> t
  val update : t -> string -> Version.t -> int -> unit
  val findVersion : cudfName:CudfName.t -> cudfVersion:int -> t -> Version.t option
  val findVersionExn : cudfName:CudfName.t -> cudfVersion:int -> t -> Version.t
  val findCudfVersion : name:string -> version:Version.t -> t -> int option
  val findCudfVersionExn : name:string -> version:Version.t -> t -> int
end = struct

  type t = {
    cudfVersionToVersion: ((CudfName.t * int), Version.t) Hashtbl.t ;
    versionToCudfVersion: ((string * Version.t), int) Hashtbl.t;
    versions : (string, Version.Set.t) Hashtbl.t;
  }

  let make ?(size=100) () = {
    cudfVersionToVersion = Hashtbl.create size;
    versionToCudfVersion = Hashtbl.create size;
    versions = Hashtbl.create size;
  }

  let update map name version cudfVersion =
    Hashtbl.replace map.versionToCudfVersion (name, version) cudfVersion;
    Hashtbl.replace map.cudfVersionToVersion (CudfName.encode name, cudfVersion) version;
    let () =
      let versions =
        try Hashtbl.find map.versions name
        with _ -> Version.Set.empty
      in
      let versions = Version.Set.add version versions in
      Hashtbl.replace map.versions name versions
    in
    ()

  let findVersion ~cudfName ~cudfVersion map =
    match Hashtbl.find map.cudfVersionToVersion (cudfName, cudfVersion) with
    | exception Not_found -> None
    | version -> Some version

  let findCudfVersion ~name ~version map =
    match Hashtbl.find map.versionToCudfVersion (name, version) with
    | exception Not_found -> None
    | version -> Some version

  let findVersionExn ~(cudfName : CudfName.t) ~cudfVersion map =
    match findVersion ~cudfName ~cudfVersion map with
    | Some v -> v
    | None ->
      let msg =
        Format.asprintf
          "inconsistent state: found a package not in the cudf version map %a@cudf:%i\n"
          CudfName.pp cudfName cudfVersion
      in
      failwith msg

  let findCudfVersionExn ~name ~version map =
    match findCudfVersion ~name ~version map with
    | Some v -> v
    | None ->
      let msg =
        Printf.sprintf
          "inconsistent state: found a package not in the cudf version map %s@%s"
          name (Version.show version)
      in
      failwith msg

end

module CudfMapping = struct

  type t = univ * Cudf.universe * CudfVersionMap.t

  let encodePkgName = CudfName.encode
  let decodePkgName = CudfName.decode

  let decodePkg (cudf : Cudf.package) (univ, _cudfUniv, vmap) =
    let cudfName = CudfName.make cudf.package in
    let name = CudfName.decode cudfName in
    match CudfVersionMap.findVersion ~cudfName ~cudfVersion:cudf.version vmap with
    | Some version -> findVersion ~name ~version univ
    | None -> None

  let decodePkgExn (cudf : Cudf.package) (univ, _cudfUniv, vmap) =
    let cudfName = CudfName.make cudf.package in
    let name = CudfName.decode cudfName in
    let version = CudfVersionMap.findVersionExn ~cudfName ~cudfVersion:cudf.version vmap in
    findVersionExn ~name ~version univ

  let encodePkg (pkg : Package.t) (_univ, cudfUniv, vmap) =
    let name = pkg.name in
    let cudfName = CudfName.encode pkg.name in
    match CudfVersionMap.findCudfVersion ~name ~version:pkg.version vmap with
    | Some cudfVersion ->
      begin
        try Some (Cudf.lookup_package cudfUniv (CudfName.show cudfName, cudfVersion))
        with | Not_found -> None
      end
    | None -> None

  let encodePkgExn (pkg : Package.t) (_univ, cudfUniv, vmap) =
    let name = pkg.name in
    let cudfName = CudfName.encode pkg.name in
    let cudfVersion = CudfVersionMap.findCudfVersionExn ~name ~version:pkg.version vmap in
    Cudf.lookup_package cudfUniv (CudfName.show cudfName, cudfVersion)

  let encodeDepExn ~name ~matches (univ, _cudfUniv, vmap)  =
    let versions = findVersions ~name univ in

    let versionsMatched =
      List.filter
        ~f:matches
        versions
    in

    match versionsMatched with
    | [] ->
      [CudfName.show (CudfName.encode name), Some (`Eq, 10000000000)]
    | versionsMatched ->
      let pkgToConstraint pkg =
        let cudfVersion =
          CudfVersionMap.findCudfVersionExn
            ~name:pkg.Package.name
            ~version:pkg.Package.version
            vmap
        in
        CudfName.show (CudfName.encode pkg.Package.name), Some (`Eq, cudfVersion)
      in
      List.map ~f:pkgToConstraint versionsMatched


  let univ (univ, _, _) = univ
  let cudfUniv (_, cudfUniv, _) = cudfUniv

end

let toCudf ?(installed=Package.Set.empty) univ =
  let cudfUniv = Cudf.empty_universe () in
  let cudfVersionMap = CudfVersionMap.make () in

  (* We add packages in batch by name so this "set of package names" is
    * enough to check if we have handled a pkg already.
    *)
  let seen, markAsSeen =
    let names = ref StringSet.empty in
    let seen name = StringSet.mem name !names in
    let markAsSeen name = names := StringSet.add name !names in
    seen, markAsSeen
  in

  let updateVersionMap pkgs =
    let f cudfVersion (pkg : Package.t) =
      CudfVersionMap.update
        cudfVersionMap
        pkg.name
        pkg.version
        (cudfVersion + 1);
    in
    List.iteri ~f pkgs;
  in

  let encodeOpamDep (dep : Package.Dep.t) =
    let versions = findVersions ~name:dep.name univ in
    if not (seen dep.name) then (
      markAsSeen dep.name;
      updateVersionMap versions;
    );
    let matches pkg =
      Resolver.versionMatchesDep
        univ.resolver
        dep
        pkg.Package.name
        pkg.Package.version
    in
    CudfMapping.encodeDepExn
      ~name:dep.name
      ~matches
      (univ, cudfUniv, cudfVersionMap)
  in

  let encodeNpmReq (req : Req.t) =
    let versions = findVersions ~name:req.name univ in
    if not (seen req.name) then (
      markAsSeen req.name;
      updateVersionMap versions;
    );
    let matches pkg =
      Resolver.versionMatchesReq
        univ.resolver
        req
        pkg.Package.name
        pkg.Package.version
    in
    CudfMapping.encodeDepExn
      ~name:req.name
      ~matches
      (univ, cudfUniv, cudfVersionMap)
  in

  let encodeDeps (deps : Dependencies.t) =
    match deps with
    | Package.Dependencies.OpamFormula deps ->
      let f deps =
        let f deps dep = deps @ (encodeOpamDep dep) in
        List.fold_left ~f ~init:[] deps
      in
      List.map ~f deps
    | Package.Dependencies.NpmFormula reqs ->
      let reqs =
        let f (req : Req.t) = StringMap.mem req.name univ.pkgs in
        List.filter ~f reqs
      in
      List.map ~f:encodeNpmReq reqs
  in

  let encodePkg pkgSize (pkg : Package.t) =
    let cudfVersion =
      CudfVersionMap.findCudfVersionExn
        ~name:pkg.name
        ~version:pkg.version
        cudfVersionMap
    in

    let depends = encodeDeps pkg.dependencies in
    let staleness = pkgSize - cudfVersion in
    let cudfName = CudfName.encode pkg.name in
    let cudfPkg = {
      Cudf.default_package with
      package = CudfName.show cudfName;
      version = cudfVersion;
      conflicts = [CudfName.show cudfName, None];
      installed = Package.Set.mem pkg installed;
      pkg_extra = [
        "staleness", `Int staleness;
        "original-version", `String (Version.show pkg.version)
      ];
      depends;
    }
    in
    Cudf.add_package cudfUniv cudfPkg
  in

  StringMap.iter (fun name _ ->
    let versions = findVersions ~name univ in
    updateVersionMap versions;
    let size = List.length versions in
    List.iter ~f:(encodePkg size) versions;
  ) univ.pkgs;

  cudfUniv, (univ, cudfUniv, cudfVersionMap)
