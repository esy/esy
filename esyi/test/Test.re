
let module Suites = {
  include Fetch;
  include Solve;
  include Npm.ParseNpm;
};

print_endline("Running tests");
TestRe.report();
