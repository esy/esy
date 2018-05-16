
[@test [
  ("let-def/wall#8b47b5ce898f6b35d6cbf92aa12baadd52f05350", Some(Types.Github("let-def", "wall", Some("8b47b5ce898f6b35d6cbf92aa12baadd52f05350")))),
  ("bsancousi/bsb-native#fast", Some(Types.Github("bsancousi", "bsb-native", Some("fast")))),
  ("v1.2.3", None)
]]
let parseGithubVersion = text => {
  let parts = Str.split(Str.regexp_string("/"), text);
  switch parts {
  | [org, rest] => {
    switch (Str.split(Str.regexp_string("#"), rest)) {
    | [repo, ref] => {
      Some(Types.Github(org, repo, Some(ref)))
    }
    | [repo] => {
      Some(Types.Github(org, repo, None))
    }
    | _ => None
    }
  }
  | _ => None
  }
};
