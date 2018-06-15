/** Solve dependencies */
let solve : (
    ~cfg : Config.t,
    ~resolutions : PackageInfo.Resolutions.t,
    Package.t
  ) => RunAsync.t(Solution.t);

let initState : (
    ~cfg : Config.t,
    ~cache : SolveState.Cache.t=?,
    ~resolutions : PackageInfo.Resolutions.t,
    Package.t
  ) => RunAsync.t(SolveState.t);
