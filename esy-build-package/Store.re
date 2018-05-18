module Path = EsyLib.Path;

let init = (path: Path.t) =>
  Run.(
    {
      let%bind () = mkdir(Path.(path / "i"));
      let%bind () = mkdir(Path.(path / "b"));
      let%bind () = mkdir(Path.(path / "s"));
      Ok();
    }
  );
