open EsyPackageConfig;

module Packument = {
  [@deriving of_yojson({strict: false})]
  type t = {
    versions: StringMap.t(Json.t),
    [@key "dist-tags"]
    distTags: StringMap.t(SemverVersion.Version.t),
  };
};

type versions = {
  versions: list(SemverVersion.Version.t),
  distTags: StringMap.t(SemverVersion.Version.t),
};

module VersionsCache =
  Memoize.Make({
    type key = string;
    type value = RunAsync.t(option(versions));
  });

module PackageCache =
  Memoize.Make({
    type key = (string, SemverVersion.Version.t);
    type value = RunAsync.t(InstallManifest.t);
  });

type t = {
  url: string,
  versionsCache: VersionsCache.t,
  pkgCache: PackageCache.t,
  queue: LwtTaskQueue.t,
};

let rec retryInCaseOfError = (~num, ~desc, f) =>
  switch%lwt (f()) {
  | Ok(resp) => RunAsync.return(resp)
  | Error(_) when num > 0 =>
    let%lwt () =
      Esy_logs_lwt.warn(m =>
        m("failed to %s, retrying (attempts left: %i)", desc, num)
      );

    retryInCaseOfError(~num=num - 1, ~desc, f);
  | Error(err) => Lwt.return(Error(err))
  };

let make = (~concurrency=40, ~url=?, ()) => {
  let url =
    switch (url) {
    | None => "http://registry.npmjs.org"
    | Some(url) =>
      let lastChar = String.length(url) - 1;

      if (url.[lastChar] == '/') {
        String.sub(url, 0, lastChar);
      } else {
        url;
      };
    };

  {
    url,
    versionsCache: VersionsCache.make(),
    pkgCache: PackageCache.make(),
    queue: LwtTaskQueue.create(~concurrency, ()),
  };
};

let versions = (~fullMetadata=false, ~name, registry, ()) => {
  open RunAsync.Syntax;
  let fetchVersions = () => {
    let fetch = {
      let name = Str.global_replace(Str.regexp("/"), "%2f", name);
      let desc = Format.asprintf("fetch %s", name);
      let accept =
        if (fullMetadata) {
          None;
        } else {
          Some("application/vnd.npm.install-v1+json");
        };

      retryInCaseOfError(~num=3, ~desc, () =>
        Curl.getOrNotFound(~accept?, registry.url ++ "/" ++ name)
      );
    };

    switch%bind (fetch) {
    | Curl.NotFound => return(None)
    | Curl.Success(data) =>
      let* packument =
        Json.parseStringWith(Packument.of_yojson, data)
        |> RunAsync.ofRun
        |> RunAsync.context("parsing packument");

      let* versions =
        RunAsync.ofStringError(
          {
            let f = ((version, packageJson)) => {
              open Result.Syntax;
              let* version = SemverVersion.Version.parse(version);
              PackageCache.ensureComputed(
                registry.pkgCache,
                (name, version),
                () => {
                  open RunAsync.Syntax;
                  let version = Version.Npm(version);
                  let* (manifest, _warnings) =
                    RunAsync.ofRun(
                      OfPackageJson.installManifest(
                        ~name,
                        ~version,
                        packageJson,
                      ),
                    );

                  return(manifest);
                },
              );
              return(version);
            };

            packument.Packument.versions
            |> StringMap.bindings
            |> Result.List.map(~f);
          },
        );
      return(Some({versions, distTags: packument.Packument.distTags}));
    };
  };

  fetchVersions
  |> LwtTaskQueue.queued(registry.queue)
  |> VersionsCache.compute(registry.versionsCache, name);
};

let package = (~name, ~version, registry, ()) => {
  open RunAsync.Syntax;
  let* _: option(versions) =
    versions(~fullMetadata=true, ~name, registry, ());
  switch (PackageCache.get(registry.pkgCache, (name, version))) {
  | None =>
    errorf(
      "no package found on npm %s@%a",
      name,
      SemverVersion.Version.pp,
      version,
    )
  | Some(pkg) => pkg
  };
};
