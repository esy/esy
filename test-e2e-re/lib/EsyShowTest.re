/* MyFirstTest.re */
open TestFramework;

module Result = EsyLib.Result;

Helpers.skipSuiteOnWindows();

describe("esy show", ({test, _}) => {
  test("shows info about packages hosted on npm", ({expect, _}) =>
    NpmMock.runWith(mockUrl => {
      open Result.Syntax;
      let%bind sandboxR = Helpers.createSandbox(~fixture=[], mockUrl);
      let sandbox: Helpers.sandboxActions = sandboxR;

      let%bind () =
        sandbox.fixtures([Fixture.defaultProject()])
        >> sandbox.defineNpmPackages([
             NpmPublish.make(~name="react", ~version="1.0.0", ()),
             NpmPublish.make(~name="react", ~version="2.0.0", ()),
           ]);
      let%bind output = sandbox.esy("show react");
      expect.string(output).toEqual(
        {|{ "name": "react", "versions": [ "2.0.0", "1.0.0" ] }|},
      );

      let%bind output = sandbox.esy("show react@1.0.0");
      expect.string(output).toEqual(
        {|
          {
            "name": "react",
            "version": "1.0.0",
            "dependencies": [],
            "devDependencies": [],
            "peerDependencies": [],
            "optDependencies": []
          }
          |}
        |> Shared.outdent,
      );
      sandbox.remove();
    })
  );

  test("shows info about packages hosted on opam", ({expect, _}) =>
    NpmMock.runWith(mockUrl => {
      open Result.Syntax;
      let%bind sandboxR = Helpers.createSandbox(~fixture=[], mockUrl);
      let sandbox: Helpers.sandboxActions = sandboxR;

      let%bind () =
        sandbox.fixtures([Fixture.defaultProject()])
        >> sandbox.defineOpamPackages([
             {
               name: "bos",
               version: "1.0.0",
               opam: {|opam-version: "2.0"|},
               url: None,
             },
             {
               name: "bos",
               version: "2.0.0",
               opam: {|opam-version: "2.0"|},
               url: None,
             },
           ]);

      let%bind output = sandbox.esy("show @opam/bos");
      expect.string(output).toEqual(
        {|{ "name": "@opam/bos", "versions": [ "2.0.0", "1.0.0" ] }|},
      );
      let%bind output = sandbox.esy("show @opam/bos@2.0.0");
      expect.string(output).toEqual(
        {|
          {
            "name": "@opam/bos",
            "version": "2.0.0",
            "dependencies": [ [ { "@esy-ocaml/substs": "*" } ] ],
            "devDependencies": [],
            "peerDependencies": [],
            "optDependencies": []
          }
          |}
        |> Shared.outdent,
      );
      sandbox.remove();
    })
  );

  test("shows info about packages hosted on github", ({expect, _}) =>
    NpmMock.runWith(mockUrl => {
      open Result.Syntax;
      let%bind sandboxR = Helpers.createSandbox(~fixture=[], mockUrl);
      let sandbox: Helpers.sandboxActions = sandboxR;

      let%bind () = sandbox.fixtures([Fixture.defaultProject()]);

      let%bind output =
        sandbox.esy("show example-yarn-package@yarnpkg/example-yarn-package");
      expect.string(output).toEqual(
        {|
          {
            "name": "example-yarn-package",
            "version":
              "github:yarnpkg/example-yarn-package#0b8f43f77361ff7739bcb42de7787b09208bcece",
            "dependencies": [ [ { "lodash": "^4.16.2" } ] ],
            "devDependencies": [ [ { "jest-cli": "=15.1.1" } ] ],
            "peerDependencies": [],
            "optDependencies": []
          }
          |}
        |> Shared.outdent,
      );

      sandbox.remove();
    })
  );
  ();
});
