open EsyPackageConfig;

module PackageOverride = {
  type t = {
    dist: Dist.t,
    override: Json.t,
  };

  let of_yojson = json => {
    open Result.Syntax;
    let* dist =
      Json.Decode.fieldWith(~name="source", Dist.relaxed_of_yojson, json);

    let* override =
      Json.Decode.fieldWith(~name="override", Json.of_yojson, json);

    return({dist, override});
  };
};

type resolution = {
  overrides: Overrides.t,
  dist: Dist.t,
  manifest: option(manifest),
  paths: Path.Set.t,
}
and manifest = {
  kind: ManifestSpec.kind,
  filename: string,
  suggestedPackageName: string,
  data: string,
};

type state =
  | EmptyManifest
  | Manifest(manifest)
  | Override(PackageOverride.t);

let rebase = (~base: Dist.t, source: Dist.t) =>
  Run.Syntax.(
    switch (source, base) {
    | (Dist.LocalPath(info), Dist.LocalPath({path: basePath, _})) =>
      let path = DistPath.rebase(~base=basePath, info.path);
      return(Dist.LocalPath({...info, path}));
    | (Dist.LocalPath(_), _) =>
      Exn.failf("unable to rebase %a onto %a", Dist.pp, source, Dist.pp, base)
    | (source, _) => return(source)
    }
  );

let suggestPackageName = (~fallback, (kind, filename)) => {
  let ensurehasOpamScope = name =>
    switch (Astring.String.cut(~sep="@opam/", name)) {
    | Some(("", _)) => name
    | Some(_)
    | None => "@opam/" ++ name
    };

  let name =
    switch (ManifestSpec.inferPackageName((kind, filename))) {
    | Some(name) => name
    | None => fallback
    };

  switch (kind) {
  | ManifestSpec.Esy => name
  | ManifestSpec.Opam => ensurehasOpamScope(name)
  };
};

let ofGithub = (~manifest=?, user, repo, ref) => {
  open RunAsync.Syntax;
  let fetchFile = name => {
    let url =
      Printf.sprintf(
        "https://raw.githubusercontent.com/%s/%s/%s/%s",
        user,
        repo,
        ref,
        name,
      );

    Curl.get(url);
  };

  let rec tryFilename = filenames =>
    switch (filenames) {
    | [] => return(EmptyManifest)
    | [(kind, filename), ...rest] =>
      switch%lwt (fetchFile(filename)) {
      | Error(_) => tryFilename(rest)
      | Ok(data) =>
        switch (kind) {
        | ManifestSpec.Esy =>
          switch (Json.parseStringWith(PackageOverride.of_yojson, data)) {
          | Ok(override) => return(Override(override))
          | Error(err) =>
            let suggestedPackageName =
              suggestPackageName(~fallback=repo, (kind, filename));
            let%lwt () =
              Esy_logs_lwt.debug(m =>
                m(
                  "not an override %s/%s:%s: %a",
                  user,
                  repo,
                  filename,
                  Run.ppError,
                  err,
                )
              );
            return(Manifest({data, filename, kind, suggestedPackageName}));
          }
        | ManifestSpec.Opam =>
          let suggestedPackageName =
            suggestPackageName(~fallback=repo, (kind, filename));
          return(Manifest({data, filename, kind, suggestedPackageName}));
        }
      }
    };

  let filenames =
    switch (manifest) {
    | Some(manifest) => [manifest]
    | None => [
        (ManifestSpec.Esy, "esy.json"),
        (ManifestSpec.Esy, "package.json"),
      ]
    };

  tryFilename(filenames);
};

let ofPath = (~pkgName, ~manifest=?, path: Path.t) => {
  open RunAsync.Syntax;

  let readManifest = ((kind, filename), manifestPath) => {
    let suggestedPackageName =
      suggestPackageName(
        ~fallback=Path.(path |> normalize |> remEmptySeg |> basename),
        (kind, filename),
      );

    if%bind (Fs.isDir(manifestPath)) {
      // manifestPath could be directory in the current state of things
      // We, ideally, make sure it's never a directory
      return(
        None,
      );
    } else {
      if%bind (Fs.exists(manifestPath)) {
        let* data = Fs.readFile(manifestPath);
        switch (kind) {
        | ManifestSpec.Esy =>
          switch (Json.parseStringWith(PackageOverride.of_yojson, data)) {
          | Ok(override) => return(Some(Override(override)))
          | Error(err) =>
            let%lwt () =
              Esy_logs_lwt.debug(m =>
                m("not an override %a: %a", Path.pp, path, Run.ppError, err)
              );

            return(
              Some(Manifest({data, filename, kind, suggestedPackageName})),
            );
          }
        | ManifestSpec.Opam =>
          return(
            Some(Manifest({data, filename, kind, suggestedPackageName})),
          )
        };
      } else {
        return(None);
      };
    };
  };

  let rec tryManifests = (tried, filenames) =>
    switch (filenames) {
    | [] => return((tried, EmptyManifest))
    | [(kind, filename), ...rest] =>
      let manifestPath = Path.(path / filename);
      let tried = Path.Set.add(manifestPath, tried);
      switch%bind (readManifest((kind, filename), manifestPath)) {
      | None => tryManifests(tried, rest)
      | Some(state) => return((tried, state))
      };
    };

  switch (manifest) {
  | Some(manifest) =>
    let* (tried, state) = tryManifests(Path.Set.empty, [manifest]);

    switch (state) {
    | EmptyManifest =>
      errorf("unable to read manifests from %a", ManifestSpec.pp, manifest)
    | state => return((tried, state))
    };
  | None =>
    let* fns = ManifestDiscovery.discover(path, pkgName);
    tryManifests(
      Path.Set.empty,
      [
        (ManifestSpec.Esy, "esy.json"),
        (ManifestSpec.Esy, "package.json"),
        (ManifestSpec.Opam, "opam"),
        ...fns |> List.map(~f=((k, fn)) => (k, Path.show(fn))),
      ],
    );
  };
};

let resolve =
    (
      ~gitUsername,
      ~gitPassword,
      ~overrides=Overrides.empty,
      ~cfg,
      ~sandbox,
      ~pkgName,
      dist: Dist.t,
    ) => {
  open RunAsync.Syntax;

  let resolve' = (dist: Dist.t) => {
    let%lwt () =
      Esy_logs_lwt.debug(m => m("fetching metadata %a", Dist.pp, dist));
    let config =
      switch (gitUsername, gitPassword) {
      | (Some(gitUsername), Some(gitPassword)) => [
          (
            "credential.helper",
            Printf.sprintf(
              "!f() { sleep 1; echo username=%s; echo password=%s; }; f",
              gitUsername,
              gitPassword,
            ),
          ),
        ]
      | _ => []
      };
    switch (dist) {
    | LocalPath({path, manifest}) =>
      let realpath = DistPath.toPath(sandbox.SandboxSpec.path, path);
      switch%bind (Fs.exists(realpath)) {
      | false => errorf("%a doesn't exist", DistPath.pp, path)
      | true =>
        let* (tried, pkg) = ofPath(~pkgName, ~manifest?, realpath);
        return((pkg, tried));
      };
    | Git({remote, commit, manifest}) =>
      Fs.withTempDir(repo => {
        let* () = Git.clone(~config, ~dst=repo, ~remote, ());
        let* () = Git.checkout(~ref=commit, ~repo, ());
        let* () = Git.updateSubmodules(~config, ~repo, ());
        let* (_, pkg) = ofPath(~pkgName, ~manifest?, repo);
        return((pkg, Path.Set.empty));
      })
    | Github({user, repo, commit, manifest}) =>
      let* pkg = ofGithub(~manifest?, user, repo, commit);
      switch (pkg) {
      | EmptyManifest =>
        let remote =
          Printf.sprintf("https://github.com/%s/%s.git", user, repo);

        Fs.withTempDir(repo => {
          let* () = Git.clone(~config, ~dst=repo, ~remote, ());
          let* () = Git.checkout(~ref=commit, ~repo, ());
          let* () = Git.updateSubmodules(~config, ~repo, ());
          let* (_, pkg) = ofPath(~pkgName, ~manifest?, repo);
          return((pkg, Path.Set.empty));
        });
      | pkg => return((pkg, Path.Set.empty))
      };
    | Archive(_) =>
      let* path = DistStorage.fetchIntoCache(cfg, sandbox, dist, None, None);
      let* (_, pkg) = ofPath(~pkgName, path);
      return((pkg, Path.Set.empty));

    | NoSource => return((EmptyManifest, Path.Set.empty))
    };
  };

  let rec loop' = (~overrides, ~paths, dist) =>
    switch%bind (resolve'(dist)) {
    | (EmptyManifest, newPaths) =>
      return({
        manifest: None,
        overrides,
        dist,
        paths: Path.Set.union(paths, newPaths),
      })
    | (Manifest(manifest), newPaths) =>
      return({
        manifest: Some(manifest),
        overrides,
        dist,
        paths: Path.Set.union(paths, newPaths),
      })
    | (Override({dist: nextDist, override: json}), newPaths) =>
      let override = Override.ofDist(json, dist);
      let* nextDist = RunAsync.ofRun(rebase(~base=dist, nextDist));
      let%lwt () =
        Esy_logs_lwt.debug(m =>
          m("override: %a -> %a@.", Dist.pp, dist, Dist.pp, nextDist)
        );
      let overrides = Overrides.add(override, overrides);
      let paths = Path.Set.union(paths, newPaths);
      loop'(~overrides, ~paths, nextDist);
    };

  loop'(~overrides, ~paths=Path.Set.empty, dist);
};
