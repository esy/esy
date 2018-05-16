let (|?>) = (a, b) => switch a { | None => None | Some(x) => b(x) };
let (|?>>) = (a, b) => switch a { | None => None | Some(x) => Some(b(x)) };
let (|?) = (a, b) => switch a { | None => b | Some(a) => a };
let (|??) = (a, b) => switch a { | None => b | Some(a) => Some(a) };
let (|!) = (a, b) => switch a { | None => failwith(b) | Some(a) => a };