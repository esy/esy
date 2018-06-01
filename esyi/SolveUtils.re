module Path = EsyLib.Path;
module Cmd = EsyLib.Cmd;

let satisfies = (realVersion, req) =>
  switch (req, realVersion) {
  | (
      PackageJson.DependencyRequest.Github(user, repo, ref),
      Solution.Version.Github(user_, repo_, ref_),
    )
      when user == user_ && repo == repo_ && ref == ref_ =>
    true
  | (Npm(semver), Solution.Version.Npm(s))
      when NpmVersion.matches(semver, s) =>
    true
  | (Opam(semver), Solution.Version.Opam(s))
      when OpamVersion.matches(semver, s) =>
    true
  | (LocalPath(p1), Solution.Version.LocalPath(p2)) when Path.equal(p1, p2) =>
    true
  | _ => false
  };

let toRealVersion = versionPlus =>
  switch (versionPlus) {
  | `Github(user, repo, ref) => Solution.Version.Github(user, repo, ref)
  | `Npm(x, _, _) => Solution.Version.Npm(x)
  | `Opam(x, _, _) => Solution.Version.Opam(x)
  | `LocalPath(p) => Solution.Version.LocalPath(p)
  };

/** TODO(jared): This is a HACK and will hopefully be removed once we stop the
 * pseudo-npm opam version stuff */
let tryConvertingOpamFromNpm = version =>
  Types.(
    version
    |> GenericVersion.map(opam =>
         switch (opam) {
         /* yay jbuilder */
         | Alpha(
             "",
             Some(
               Num(
                 major,
                 Some(
                   Alpha(
                     ".",
                     Some(
                       Num(
                         minor,
                         Some(
                           Alpha(
                             ".",
                             Some(Num(0, Some(Alpha("-beta", rest)))),
                           ),
                         ),
                       ),
                     ),
                   ),
                 ),
               ),
             ),
           ) =>
           Alpha(
             "",
             Some(
               Num(
                 major,
                 Some(
                   Alpha(
                     ".",
                     Some(Num(minor, Some(Alpha("+beta", rest)))),
                   ),
                 ),
               ),
             ),
           )
         | Alpha(
             "",
             Some(
               Num(
                 major,
                 Some(
                   Alpha(
                     ".",
                     Some(
                       Num(minor, Some(Alpha(".", Some(Num(0, post))))),
                     ),
                   ),
                 ),
               ),
             ),
           ) =>
           Alpha(
             "",
             Some(Num(major, Some(Alpha(".", Some(Num(minor, post)))))),
           )
         | _ => opam
         }
       )
  );

let expectSuccess = (msg, v) =>
  if (v) {
    ();
  } else {
    failwith(msg);
  };

let rec lockDownSource = pendingSource =>
  RunAsync.Syntax.(
    switch (pendingSource) {
    | Types.PendingSource.NoSource => return((Solution.Source.NoSource, None))
    | WithOpamFile(source, opamFile) =>
      switch%bind (lockDownSource(source)) {
      | (s, None) => return((s, Some(opamFile)))
      | _ => error("can't nest withOpamFiles inside each other")
      }
    | Archive(url, None) =>
      return((
        /* print_endline("Pretending to get a checksum for " ++ url); */
        Solution.Source.Archive(url, "fake checksum"),
        None,
      ))
    | Archive(url, Some(checksum)) =>
      return((Solution.Source.Archive(url, checksum), None))
    | GitSource(url, ref) =>
      let ref = Option.orDefault(~default="master", ref);
      /** TODO getting HEAD */
      let%bind sha = Git.lsRemote(~remote=url, ~ref, ());
      return((Solution.Source.GitSource(url, sha), None));
    | GithubSource(user, name, ref) =>
      let ref = Option.orDefault(~default="master", ref);
      let url = "git://github.com/" ++ user ++ "/" ++ name ++ ".git";
      let%bind sha = Git.lsRemote(~remote=url, ~ref, ());
      return((Solution.Source.GithubSource(user, name, sha), None));
    | File(s) => return((Solution.Source.File(s), None))
    }
  );

let checkRepositories = config =>
  RunAsync.Syntax.(
    {
      let%bind () =
        Git.ShallowClone.update(
          ~branch="4",
          ~dst=config.Config.esyOpamOverridePath,
          "https://github.com/esy-ocaml/esy-opam-override",
        );
      let%bind () =
        Git.ShallowClone.update(
          ~branch="master",
          ~dst=config.Config.opamRepositoryPath,
          "https://github.com/ocaml/opam-repository",
        );
      return();
    }
  );

let getCachedManifest = (opamOverrides, cache, (name, versionPlus)) => {
  let realVersion = toRealVersion(versionPlus);
  switch (Hashtbl.find(cache, (name, realVersion))) {
  | exception Not_found =>
    let manifest =
      switch (versionPlus) {
      | `Github(user, repo, ref) => Github.getManifest(name, user, repo, ref)
      /* Registry.getGithubManifest(url) */
      | `Npm(_version, json, _) => Manifest.PackageJson(json)
      | `LocalPath(_p) =>
        failwith("do not know how to get manifest from LocalPath")
      | `Opam(_version, path, _) =>
        let manifest =
          OpamRegistry.getManifest(opamOverrides, path)
          |> RunAsync.runExn(~err="unable to read opam manifest");
        Manifest.Opam(manifest);
      };
    let depsByKind = Manifest.getDeps(manifest);
    let res = (manifest, depsByKind);
    Hashtbl.replace(cache, (name, realVersion), res);
    res;
  | x => x
  };
};

let runSolver = (~strategy="-notuptodate", rootName, deps, universe) => {
  let root = {
    ...Cudf.default_package,
    package: rootName,
    version: 1,
    depends: deps,
  };
  Cudf.add_package(universe, root);
  let request = {
    ...Cudf.default_request,
    install: [(root.Cudf.package, Some((`Eq, root.Cudf.version)))],
  };
  let preamble = Cudf.default_preamble;
  let solution =
    Mccs.resolve_cudf(
      ~verbose=false,
      ~timeout=5.,
      strategy,
      (preamble, universe, request),
    );
  switch (solution) {
  | None => None
  | Some((_preamble, universe)) =>
    let packages = Cudf.get_packages(~filter=p => p.Cudf.installed, universe);
    Some(packages);
  };
};

let getOpamFile = (manifest, name, version) =>
  switch (manifest) {
  | Manifest.PackageJson(_) => None
  | Manifest.Opam(manifest) =>
    Some(OpamFile.toPackageJson(manifest, name, version))
  };
