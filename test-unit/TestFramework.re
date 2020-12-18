include Rely.Make({
  let config =
    Rely.TestFrameworkConfig.initialize({
      snapshotDir: "./test-unit/__snapshots__",
      projectDir: ".",
    });
});
