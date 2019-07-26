/* TestFramework.re */
include Rely.Make({
  let config =
    Rely.TestFrameworkConfig.initialize({
      snapshotDir: "./test-e2e-re/lib/__snapshots__",
      projectDir: ".",
    });
});
