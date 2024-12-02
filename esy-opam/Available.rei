let evalAvailabilityFilter:
  (~os: System.Platform.t, ~arch: System.Arch.t, OpamTypes.filter) => bool;
/**

   [eval(~os, ~arch, filter)] evaluates availability filter, [filter] and
   determines if the package is available.

 */
let eval: (~os: System.Platform.t, ~arch: System.Arch.t, string) => bool;
