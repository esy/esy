open RunAsync.Syntax;

let filename = "projects.json";

let init = prefixPath => {
  let pathToProjects = Path.(prefixPath / filename);
  if%bind (Fs.exists(pathToProjects)) {
    return();
  } else {
    Fs.writeJsonFile(~json=`List([]), pathToProjects);
  };
};

let get = prefixPath => {
  let* () = init(prefixPath);
  let projectsPath = Path.(prefixPath / "projects.json");
  let* json = Fs.readJsonFile(projectsPath);
  let* json =
    switch (Json.Decode.(list(string, json))) {
    | Ok(json) => return(json)
    | Error(err) => errorf("%s cannot be parsed", projectsPath |> Path.show)
    };
  json |> List.map(~f=Path.v) |> return;
};

let update = (prefixPath, currentProj) => {
  open Json;
  let* () = init(prefixPath);
  let projectsPath = Path.(prefixPath / "projects.json");
  let* json = Fs.readJsonFile(projectsPath);
  let* projects =
    switch (Decode.(list(string, json))) {
    | Ok(projects) =>
      let projects =
        if (List.mem(currentProj, ~set=projects)) {
          projects;
        } else {
          [currentProj, ...projects];
        };
      let* projects =
        RunAsync.List.filter(
          ~f=
            project => {
              switch (Path.ofString(project)) {
              | Ok(path) =>
                if%bind (Fs.exists(path)) {
                  RunAsync.return(true);
                } else {
                  RunAsync.return(false);
                }
              | Error(`Msg(_)) => RunAsync.return(false)
              }
            },
          projects,
        );
      Encode.(list(string, projects)) |> return;
    | Error(_err) => errorf("%s cannot be parsed", projectsPath |> Path.show)
    };
  Fs.writeJsonFile(~json=projects, projectsPath);
};
