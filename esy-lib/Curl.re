module String = Astring.String;

type response =
  | Success(string)
  | NotFound;

type headers = StringMap.t(string);

type url = string;

let parseStdout = stdout =>
  Run.Syntax.(
    switch (String.cut(~rev=true, ~sep="\n", stdout)) {
    | Some((stdout, httpcode)) =>
      let* httpcode =
        try(return(int_of_string(httpcode))) {
        | Failure(_) => errorf("unable to parse HTTP code: %s", httpcode)
        };

      return((stdout, httpcode));
    | None => error("unable to parse metadata from a curl response")
    }
  );

let runCurl = cmd => {
  let cmd = Cmd.(cmd % "--write-out" % {|\n%{http_code}|});
  let f = p => {
    let%lwt stdout =
      Lwt.finalize(
        () => Lwt_io.read(p#stdout),
        () => Lwt_io.close(p#stdout),
      )
    and stderr = Lwt_io.read(p#stderr);
    switch%lwt (p#status) {
    | Unix.WEXITED(0) =>
      switch (parseStdout(stdout)) {
      | [@implicit_arity] Ok(stdout, _httpcode) =>
        RunAsync.return(Success(stdout))
      | Error(err) => Lwt.return(Error(err))
      }
    | _ =>
      switch (parseStdout(stdout)) {
      | [@implicit_arity] Ok(_stdout, httpcode) when httpcode == 404 =>
        RunAsync.return(NotFound)
      | [@implicit_arity] Ok(_stdout, httpcode) =>
        RunAsync.errorf(
          "@[<v>error running curl: %a:@\ncode: %i@\nstderr:@[<v 2>@\n%a@]@]",
          Cmd.pp,
          cmd,
          httpcode,
          Fmt.lines,
          stderr,
        )
      | _ =>
        RunAsync.errorf(
          "@[<v>error running curl: %a:@\nstderr:@[<v 2>@\n%a@]@]",
          Cmd.pp,
          cmd,
          Fmt.lines,
          stderr,
        )
      }
    };
  };

  try%lwt(EsyBashLwt.with_process_full(cmd, f)) {
  | [@implicit_arity] Unix.Unix_error(err, _, _) =>
    let msg = Unix.error_message(err);
    RunAsync.error(msg);
  | exn =>
    RunAsync.errorf(
      "error running subprocess %s",
      Printexc.exn_slot_name(exn),
    )
  };
};

let getOrNotFound = (~accept=?, url) => {
  let cmd =
    Cmd.(
      v("curl")
      % "--silent"
      % "--connect-timeout"
      % "60"
      % "--retry"
      % "3"
      % "--retry-delay"
      % "5"
      % "--fail"
      % "--location"
      % url
    );
  let cmd =
    switch (accept) {
    | Some(accept) => Cmd.(cmd % "--header" % accept)
    | None => cmd
    };

  runCurl(cmd);
};

let head = url => {
  open RunAsync.Syntax;

  let parseResponse = response =>
    switch (StringLabels.split_on_char(~sep='\n', response)) {
    | [] => StringMap.empty
    | [_, ...lines] =>
      let f = (headers, line) =>
        switch (String.cut(~sep=":", line)) {
        | None => headers
        | Some((name, value)) =>
          let name = name |> String.trim |> String.Ascii.lowercase;
          let value = String.trim(value);
          StringMap.add(name, value, headers);
        };

      List.fold_left(~f, ~init=StringMap.empty, lines);
    };

  let cmd =
    Cmd.(
      v("curl")
      % "--head"
      % "--silent"
      % "--connect-timeout"
      % "60"
      % "--retry"
      % "3"
      % "--retry-delay"
      % "5"
      % "--fail"
      % "--location"
      % url
    );
  switch%bind (runCurl(cmd)) {
  | Success(response) => return(parseResponse(response))
  | NotFound => RunAsync.error("not found")
  };
};

let get = (~accept=?, url) => {
  open RunAsync.Syntax;
  switch%bind (getOrNotFound(~accept?, url)) {
  | Success(result) => RunAsync.return(result)
  | NotFound => RunAsync.error("not found")
  };
};

let download = (~output, url) => {
  open RunAsync.Syntax;
  let output = EsyBash.normalizePathForCygwin(Path.show(output));
  let cmd =
    Cmd.(
      v("curl")
      % "--silent"
      % "--connect-timeout"
      % "60"
      % "--retry"
      % "3"
      % "--retry-delay"
      % "5"
      % "--fail"
      % "--location"
      % url
      % "--output"
      % output
    );
  switch%bind (runCurl(cmd)) {
  | Success(_) => RunAsync.return()
  | NotFound => RunAsync.error("not found")
  };
};
