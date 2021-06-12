type ref = string;
type commit = string;
type remote = string;

let runGit = cmd => {
  let f = p => {
    let%lwt stdout = Lwt_io.read(p#stdout)
    and stderr = Lwt_io.read(p#stderr);
    switch%lwt (p#status) {
    | Unix.WEXITED(0) => RunAsync.return(stdout)
    | _ =>
      RunAsync.errorf(
        "@[<v>command failed: %a@\nstderr:@[<v 2>@\n%a@]@\nstdout:@[<v 2>@\n%a@]@]",
        Cmd.pp,
        cmd,
        Fmt.lines,
        stderr,
        Fmt.lines,
        stdout,
      )
    };
  };

  try%lwt(EsyBashLwt.with_process_full(cmd, f)) {
  | [@implicit_arity] Unix.Unix_error(err, _, _) =>
    let msg = Unix.error_message(err);
    RunAsync.error(msg);
  | _ => RunAsync.errorf("cannot execute command: %a", Cmd.pp, cmd)
  };
};

let updateSubmodules = (~repo, ~config as configKVs=?, ()) => {
  open RunAsync.Syntax;
  let repo = EsyBash.normalizePathForCygwin(Path.show(repo));
  let cmd = Cmd.v("git");
  let cmd =
    switch (configKVs) {
    | Some([])
    | None => cmd
    | Some(cs) =>
      List.fold_left(
        ~f=
          (accCmd, cfg) => {
            let (k, v) = cfg;
            let configKVs = Printf.sprintf("%s=%s", k, v);
            Cmd.(accCmd % "-c" % configKVs);
          },
        ~init=cmd,
        cs,
      )
    };
  let cmd =
    Cmd.(
      cmd % "-C" % repo % "submodule" % "update" % "--init" % "--recursive"
    );
  let* _ = runGit(cmd);
  return();
};

let clone = (~branch=?, ~config as configKVs=?, ~depth=?, ~dst, ~remote, ()) => {
  open RunAsync.Syntax;
  let* cmd =
    RunAsync.ofBosError(
      {
        open Cmd;
        open Result.Syntax;
        let dest = EsyBash.normalizePathForCygwin(Path.show(dst));
        let cmd = v("git");
        let cmd =
          switch (configKVs) {
          | Some([])
          | None => cmd
          | Some(cs) =>
            List.fold_left(
              ~f=
                (accCmd, cfg) => {
                  let (k, value) = cfg;
                  accCmd % "-c" % Printf.sprintf("%s=%s", k, value);
                },
              ~init=cmd,
              cs,
            )
          };

        let cmd = cmd % "clone";

        let cmd =
          switch (branch) {
          | Some(branch) => cmd % "--branch" % branch
          | None => cmd
          };

        let cmd =
          switch (depth) {
          | Some(depth) => cmd % "--depth" % string_of_int(depth)
          | None => cmd
          };

        return(Cmd.(cmd % remote % dest));
      },
    );

  let* _ = runGit(cmd);
  return();
};

let revParse = (~repo, ~ref, ()) => {
  let cmd = Cmd.(v("git") % "rev-parse" % "-C" % p(repo) % ref);
  runGit(cmd);
};

let fetch = (~depth=?, ~dst, ~ref, ~remote, ()) => {
  let cmd = Cmd.(v("git") % "-C" % Path.show(dst) % "fetch" % remote % ref);
  let cmd =
    switch (depth) {
    | Some(depth) => Cmd.(cmd % "--depth" % string_of_int(depth))
    | None => cmd
    };
  let%lwt _ = runGit(cmd);
  RunAsync.return();
};

let pull =
    (~force=false, ~ffOnly=false, ~depth=?, ~remote, ~repo, ~branchSpec, ()) => {
  open RunAsync.Syntax;
  let cmd = {
    open Cmd;
    let cmd = v("git") % "-C" % p(repo) % "pull";
    let cmd = ffOnly ? cmd % "--ff-only" : cmd;

    let cmd = force ? cmd % "--force" : cmd;

    let cmd =
      switch (depth) {
      | Some(depth) => cmd % "--depth" % string_of_int(depth)
      | None => cmd
      };

    Cmd.(cmd % remote % branchSpec);
  };

  let* _ = runGit(cmd);
  return();
};

let checkout = (~ref, ~repo, ()) => {
  open RunAsync.Syntax;
  let cmd = Cmd.(v("git") % "-C" % p(repo) % "checkout" % ref);
  let* _ = runGit(cmd);
  return();
};

let lsRemote = (~config as configKVs=?, ~ref=?, ~remote, ()) => {
  open RunAsync.Syntax;
  let cmd = Cmd.(v("git"));
  let cmd =
    switch (configKVs) {
    | Some([])
    | None => cmd
    | Some(cs) =>
      List.fold_left(
        ~f=
          (accCmd, cfg) => {
            let (k, v) = cfg;
            let configOption = Printf.sprintf("%s=%s", k, v);
            Cmd.(accCmd % "-c" % configOption);
          },
        ~init=cmd,
        cs,
      )
    };

  let cmd = Cmd.(cmd % "ls-remote" % remote);

  let cmd =
    switch (ref) {
    | Some(ref) => Cmd.(cmd % ref)
    | None => cmd
    };

  let* out = runGit(cmd);
  switch (out |> String.trim |> String.split_on_char('\n')) {
  | [] => return(None)
  | [line, ..._] =>
    let commit = line |> String.split_on_char('\t') |> List.hd;
    if (commit == "") {
      return(None);
    } else {
      return(Some(commit));
    };
  };
};

let isCommitLikeRe = Str.regexp("^[0-9abcdef]+$");
let isCommitLike = v => {
  let len = String.length(v);
  if (len >= 6) {
    Str.string_match(isCommitLikeRe, v, 0);
  } else {
    false;
  };
};

module ShallowClone = {
  let update = (~gitUsername=?, ~gitPassword=?, ~branch, ~dst, source) => {
    let gitConfig =
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
    let getLocalCommit = () => {
      let remote = EsyBash.normalizePathForCygwin(Path.show(dst));
      lsRemote(~remote, ~config=gitConfig, ());
    };

    let rec aux = (~retry=true, ()) => {
      open RunAsync.Syntax;
      if%bind (Fs.exists(dst)) {
        let* remoteCommit =
          lsRemote(~config=gitConfig, ~ref=branch, ~remote=source, ());
        let* localCommit = getLocalCommit();

        if (remoteCommit == localCommit) {
          return();
        } else {
          let branchSpec = branch ++ ":" ++ branch;
          let pulling =
            pull(
              ~branchSpec,
              ~force=true,
              ~depth=1,
              ~remote=source,
              ~repo=dst,
              (),
            );

          switch%lwt (pulling) {
          | Ok(_) => return()
          | Error(_) when retry =>
            let* () = Fs.rmPath(dst);
            aux(~retry=false, ());
          | Error(err) => Lwt.return(Error(err))
          };
        };
      } else {
        let* () = Fs.createDir(Path.parent(dst));
        let* () = clone(~branch, ~depth=1, ~remote=source, ~dst, ());
        return();
      };
    };

    aux();
  };
};
