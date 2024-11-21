/**

   Evaluates available field (cached in lock file) and determines if the package is available.

   Assumes [available] is currently only an opam filter, which means this function must be a no-op on
   NPM packages. Atleast till designed takes into account [platform] and [arch] fields in NPM manifests
 */
let eval: Package.t => bool;
