/**

     These modules represent an entry (a package) in node_modules folder.
     packages in the node_modules folder have be unique by name. JS
     packages in the graph could have more one versions present - we
     have to carefully avoid conflicts and save disk space.

*/
type t = Solution.pkg;
let compare: (t, t) => int;

let pp: Fmt.t(t);
let name: t => string;
let version: t => EsyPackageConfig.Version.t;
