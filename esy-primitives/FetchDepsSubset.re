open DepSpec;

type t = {
  all: FetchDepSpec.t,
  dev: FetchDepSpec.t,
};

let everything = {
  let all = FetchDepSpec.(dependencies(self) + devDependencies(self));
  {all, dev: all};
};
