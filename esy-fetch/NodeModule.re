type t = Solution.pkg;

let compare = (a, b) => Package.(String.compare(a.name, b.name));

let pp = Package.pp;
let name = (Package.{name, _}) => name;
let version = (Package.{version, _}) => version;
