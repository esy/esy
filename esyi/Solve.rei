/** Solve dependencies */
let solve : (
    ~cfg : Config.t,
    ~resolutions : PackageInfo.Resolutions.t,
    Package.t
  ) => RunAsync.t(Solution.t);
