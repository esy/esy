let init = (path: Path.t) =>
  Run.(
    {
      let%bind () = mkdir(Fpath.(path / "i"));
      let%bind () = mkdir(Fpath.(path / "b"));
      let%bind () = mkdir(Fpath.(path / "s"));
      Ok();
    }
  );
