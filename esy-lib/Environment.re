module Binding = {
  [@deriving ord]
  type t('v) = {
    name: string,
    value: value('v),
    origin: option(string),
  }
  and value('v) =
    | Value('v)
    | ExpandedValue('v)
    | Prefix('v)
    | Suffix('v)
    | Remove;

  let origin = binding => binding.origin;

  let pp = (ppValue, fmt, binding) =>
    switch (binding.value) {
    | Value(v) => Fmt.pf(fmt, "%s=%a", binding.name, ppValue, v)
    | ExpandedValue(v) => Fmt.pf(fmt, "%s=%a", binding.name, ppValue, v)
    | Prefix(v) =>
      Fmt.pf(fmt, "%s=%a:%s", binding.name, ppValue, v, binding.name)
    | Suffix(v) =>
      Fmt.pf(fmt, "%s=%s:%a", binding.name, binding.name, ppValue, v)
    | Remove => Fmt.pf(fmt, "unset %s", binding.name)
    };
};

module type S = {
  type ctx;
  type value;

  type t = StringMap.t(value);
  type env = t;

  let empty: t;
  let find: (string, t) => option(value);
  let add: (string, value, t) => t;
  let map: (~f: string => string, t) => t;

  let render: (ctx, t) => StringMap.t(string);

  include S.COMPARABLE with type t := t;
  include S.JSONABLE with type t := t;

  module Bindings: {
    type t = list(Binding.t(value));

    let pp: Fmt.t(t);

    let value: (~origin: string=?, string, value) => Binding.t(value);
    let prefixValue: (~origin: string=?, string, value) => Binding.t(value);
    let suffixValue: (~origin: string=?, string, value) => Binding.t(value);
    let remove: (~origin: string=?, string) => Binding.t(value);

    let empty: t;
    let render: (ctx, t) => list(Binding.t(string));
    let eval:
      (~platform: System.Platform.t=?, ~init: env=?, t) => result(env, string);
    let map: (~f: string => string, t) => t;

    let current: t;

    include S.COMPARABLE with type t := t;
  };
};

module Make =
       (V: Abstract.STRING)
       : {include S with type value = V.t and type ctx = V.ctx;} => {
  type value = V.t;
  type ctx = V.ctx;

  [@deriving (ord, yojson)]
  type t = StringMap.t(V.t);

  type env = t;

  let add = StringMap.add;
  let empty = StringMap.empty;
  let find = StringMap.find;
  let map = (~f, env) => {
    let f = value => value |> V.show |> f |> V.v;
    StringMap.map(f, env);
  };

  let render = (ctx, env) => {
    let f = (name, value, map) => {
      let value = V.render(ctx, value);
      StringMap.add(name, value, map);
    };

    StringMap.fold(f, env, StringMap.empty);
  };

  module Bindings = {
    [@deriving ord]
    type t = list(Binding.t(V.t));

    let pp = Fmt.(vbox(list(~sep=any("@;"), Binding.pp(V.pp))));

    let empty = [];
    let value = (~origin=?, name, value) => {
      Binding.name,
      value: Value(value),
      origin,
    };

    let prefixValue = (~origin=?, name, value) => {
      let value = Binding.Prefix(value);
      {Binding.name, value, origin};
    };

    let suffixValue = (~origin=?, name, value) => {
      let value = Binding.Suffix(value);
      {Binding.name, value, origin};
    };

    let remove = (~origin=?, name) => {Binding.name, value: Remove, origin};

    let map = (~f, bindings) => {
      let f = binding => {
        let value =
          switch (binding.Binding.value) {
          | Binding.Value(value) =>
            Binding.Value(value |> V.show |> f |> V.v)
          | Binding.ExpandedValue(value) =>
            Binding.ExpandedValue(value |> V.show |> f |> V.v)
          | Binding.Prefix(value) =>
            Binding.Prefix(value |> V.show |> f |> V.v)
          | Binding.Suffix(value) =>
            Binding.Suffix(value |> V.show |> f |> V.v)
          | Binding.Remove => Binding.Remove
          };

        {...binding, value};
      };

      List.map(~f, bindings);
    };

    let render = (ctx, bindings) => {
      let f = ({Binding.name, value, origin}) => {
        let value =
          switch (value) {
          | Binding.ExpandedValue(value) =>
            Binding.ExpandedValue(V.render(ctx, value))
          | Binding.Value(value) => Binding.Value(V.render(ctx, value))
          | Binding.Prefix(value) => Binding.Prefix(V.render(ctx, value))
          | Binding.Suffix(value) => Binding.Suffix(V.render(ctx, value))
          | Binding.Remove => Binding.Remove
          };

        {Binding.name, value, origin};
      };

      List.map(~f, bindings);
    };

    let eval =
        (~platform=System.Platform.host, ~init=StringMap.empty, bindings) => {
      open Result.Syntax;

      let f = (env, binding) => {
        let scope = name =>
          switch (StringMap.find(name, env)) {
          | Some(v) => Some(V.show(v))
          | None => None
          };

        switch (binding.Binding.value) {
        | Value(value) =>
          let value = V.show(value);
          let* value = EsyShellExpansion.render(~scope, value);
          let value = V.v(value);
          Ok(StringMap.add(binding.name, value, env));
        | ExpandedValue(value) =>
          Ok(StringMap.add(binding.name, value, env))
        | Prefix(value) =>
          let value = V.show(value);
          let value =
            switch (StringMap.find(binding.name, env)) {
            | Some(prevValue) =>
              let sep =
                System.Environment.sep(~platform, ~name=binding.name, ());
              value ++ sep ++ V.show(prevValue);
            | None => value
            };

          let value = V.v(value);
          Ok(StringMap.add(binding.name, value, env));
        | Suffix(value) =>
          let value = V.show(value);
          let value =
            switch (StringMap.find(binding.name, env)) {
            | Some(prevValue) =>
              let sep =
                System.Environment.sep(~platform, ~name=binding.name, ());
              V.show(prevValue) ++ sep ++ value;
            | None => value
            };

          let value = V.v(value);
          Ok(StringMap.add(binding.name, value, env));
        | Remove => Ok(StringMap.remove(binding.name, env))
        };
      };

      Result.List.foldLeft(~f, ~init, bindings);
    };

    let current = {
      let parseEnv = item => {
        let idx = String.index(item, '=');
        let name = String.sub(item, 0, idx);
        let name =
          switch (System.Platform.host) {
          | System.Platform.Windows => String.uppercase_ascii(name)
          | _ => name
          };

        let value = String.sub(item, idx + 1, String.length(item) - idx - 1);
        {Binding.name, value: ExpandedValue(V.v(value)), origin: None};
      };

      /* Filter bash function which are being exported in env */
      let filterInvalidNames = ({Binding.name, _}) => {
        let starting = "BASH_FUNC_";
        let ending = "%%";
        !(
          String.length(name) > String.length(starting)
          && Str.first_chars(name, String.length(starting)) == starting
          && Str.last_chars(name, String.length(ending)) == ending
          || String.contains(name, '.')
        );
      };

      Unix.environment()
      |> Array.map(parseEnv)
      |> Array.to_list
      |> List.filter(~f=filterInvalidNames);
    };
  };
};

module V =
  Make({
    include String;
    type ctx = unit;
    let v = v => v;
    let of_yojson = Json.Decode.string;
    let to_yojson = v => `String(v);
    let show = v => v;
    let pp = Fmt.string;
    let render = ((), v) => v;
  });

include V;

let escapeDoubleQuote = value => {
  let re = Str.regexp("\"");
  Str.global_replace(re, "\\\"", value);
};

let escapeSingleQuote = value => {
  let re = Str.regexp("'");
  Str.global_replace(re, "''", value);
};

let renderToShellSource =
    (
      ~header="# Environment",
      ~platform=System.Platform.host,
      bindings: list(Binding.t(string)),
    ) => {
  open Run.Syntax;
  let emptyLines =
    fun
    | [] => true
    | _ => false;

  let f = ((lines, prevOrigin), {Binding.name, value, origin}) => {
    let lines =
      if (prevOrigin != origin || emptyLines(lines)) {
        let header =
          switch (origin) {
          | Some(origin) => Printf.sprintf("\n#\n# %s\n#", origin)
          | None => "\n#\n# Built-in\n#"
          };
        [header, ...lines];
      } else {
        lines;
      };

    let* line =
      switch (value) {
      | Value(value) =>
        let value = escapeDoubleQuote(value);
        Ok(Printf.sprintf("export %s=\"%s\"", name, value));
      | ExpandedValue(value) =>
        let value = escapeSingleQuote(value);
        Ok(Printf.sprintf("export %s='%s'", name, value));
      | Prefix(value) =>
        let sep = System.Environment.sep(~platform, ~name, ());
        let value = escapeDoubleQuote(value);
        Ok(Printf.sprintf("export %s=\"%s%s$%s\"", name, value, sep, name));
      | Suffix(value) =>
        let sep = System.Environment.sep(~platform, ~name, ());
        let value = escapeDoubleQuote(value);
        Ok(Printf.sprintf("export %s=\"$%s%s%s\"", name, name, sep, value));
      | Remove => Ok(Printf.sprintf("unset %s", name))
      };

    [@implicit_arity] Ok([line, ...lines], origin);
  };

  let* (lines, _) = Run.List.foldLeft(~f, ~init=([], None), bindings);
  return(header ++ "\n" ++ (lines |> List.rev |> String.concat("\n")));
};

let renderToList = (~platform=System.Platform.host, bindings) => {
  let f = ({Binding.name, value, origin: _}) => {
    let value =
      switch (value) {
      | Binding.Value(value) => value
      | Binding.ExpandedValue(value) => value
      | Binding.Prefix(value) =>
        let sep = System.Environment.sep(~platform, ~name, ());
        value ++ sep ++ "$" ++ name;
      | Binding.Suffix(value) =>
        let sep = System.Environment.sep(~platform, ~name, ());
        "$" ++ name ++ sep ++ value;
      // TODO: is that correct?
      | Binding.Remove => ""
      };

    (name, value);
  };

  List.map(~f, bindings);
};
