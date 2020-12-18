open TestFramework;
open TestUnitFs.Fs;
open EsyBuildPackage;
open Build;

describe("Fs", ({test, _}) => {
  test(
    "Fs.getBinMachOs: return three mach-o's from the mocked file system",
    ({expect, _}) => {
    switch (
      getMachOBins(
        (module Mock.Fs): (module Run.T),
        [],
        Fpath.v("dirdirdir"),
      )
    ) {
    | Ok(l) => expect.int(List.length(l)).toBe(6)
    | Error(`Msg(m)) => failwith(m)
    | Error(`CommandError(_)) => failwith("Command Error")
    }
  })
});
