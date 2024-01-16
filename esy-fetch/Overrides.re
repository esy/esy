open RunAsync.Syntax;

let fetch = (cfg, sandbox, overrides) => {
  let f = (files, override) => {
    let* filesOfOverride = Override.fetch(cfg, sandbox, override);
    return(filesOfOverride @ files);
  };

  let fold' = (~f, ~init, overrides) =>
    RunAsync.List.foldLeft(~f, ~init, List.rev(overrides));

  fold'(~f, ~init=[], overrides);
};
