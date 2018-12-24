type t = {
  cfg : Config.t;
  spec : SandboxSpec.t;
}

let make cfg spec = {cfg; spec;}
