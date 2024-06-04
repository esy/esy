open EsyPackageConfig;
open RunAsync.Syntax;
let fetch = (~cachedSourcesPath, ~stagePath, extraSources) => {
  let* () = Fs.createDir(cachedSourcesPath);
  let%bind () = Fs.createDir(stagePath);
  RunAsync.List.mapAndWait(
    ~f=
      ({ExtraSource.url, checksum, relativePath}) => {
        open RunAsync.Syntax;
        let downloadPath = Path.(stagePath / relativePath);
        let* _ = Curl.download(~output=downloadPath, url);
        let* _ = Checksum.checkFile(~path=downloadPath, checksum);
        let* _ =
          Fs.rename(
            ~skipIfExists=true,
            ~src=downloadPath,
            Path.(cachedSourcesPath / relativePath),
          );
        RunAsync.return();
      },
    extraSources,
  );
};
