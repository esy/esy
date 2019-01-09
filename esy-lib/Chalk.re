/**
 * Chalk.
 * https://gist.github.com/kyldvs/24793e33e0d88f7396e50a6aedcbda87
 *
 * Copyright 2004-present Facebook. All Rights Reserved.
 */
module IntMap =
  Map.Make({
    type t = int;
    let compare = compare;
  });

module IntSet =
  Set.Make({
    type t = int;
    let compare = compare;
  });

module Ansi = {
  type style = {
    start: string,
    startCode: int,
    stop: string,
    stopCode: int,
  };
  let createStyle = (start: int, stop: int): style => {
    start: "\027[" ++ string_of_int(start) ++ "m",
    startCode: start,
    stop: "\027[" ++ string_of_int(stop) ++ "m",
    stopCode: stop,
  };
  type modifier = {
    reset: string,
    bold: style,
    dim: style,
    italic: style,
    underline: style,
    inverse: style,
    hidden: style,
    strikethrough: style,
  };
  type color = {
    stop: string,
    /* Normal colors */
    black: style,
    red: style,
    green: style,
    yellow: style,
    blue: style,
    magenta: style,
    cyan: style,
    white: style,
    gray: style,
    /* For humans */
    grey: style,
    /* Bright colors */
    redBright: style,
    greenBright: style,
    yellowBright: style,
    blueBright: style,
    magentaBright: style,
    cyanBright: style,
    whiteBright: style,
  };
  type bg = {
    stop: string,
    /* Normal colors */
    black: style,
    red: style,
    green: style,
    yellow: style,
    blue: style,
    magenta: style,
    cyan: style,
    white: style,
    /* Bright colors */
    blackBright: style,
    redBright: style,
    greenBright: style,
    yellowBright: style,
    blueBright: style,
    magentaBright: style,
    cyanBright: style,
    whiteBright: style,
  };
  let modifier: modifier = {
    reset: "\027[0m",
    /* 21 isn't widely supported and 22 does the same thing */
    bold: createStyle(1, 22),
    dim: createStyle(2, 22),
    italic: createStyle(3, 23),
    underline: createStyle(4, 24),
    inverse: createStyle(7, 27),
    hidden: createStyle(8, 28),
    strikethrough: createStyle(9, 29),
  };
  let color: color = {
    stop: "\027[39m",
    black: createStyle(30, 39),
    red: createStyle(31, 39),
    green: createStyle(32, 39),
    yellow: createStyle(33, 39),
    blue: createStyle(34, 39),
    magenta: createStyle(35, 39),
    cyan: createStyle(36, 39),
    white: createStyle(37, 39),
    gray: createStyle(90, 39),
    grey: createStyle(90, 39),
    redBright: createStyle(91, 39),
    greenBright: createStyle(92, 39),
    yellowBright: createStyle(93, 39),
    blueBright: createStyle(94, 39),
    magentaBright: createStyle(95, 39),
    cyanBright: createStyle(96, 39),
    whiteBright: createStyle(97, 39),
  };
  let bg: bg = {
    stop: "\027[49m",
    black: createStyle(40, 49),
    red: createStyle(41, 49),
    green: createStyle(42, 49),
    yellow: createStyle(43, 49),
    blue: createStyle(44, 49),
    magenta: createStyle(45, 49),
    cyan: createStyle(46, 49),
    white: createStyle(47, 49),
    blackBright: createStyle(100, 49),
    redBright: createStyle(101, 49),
    greenBright: createStyle(102, 49),
    yellowBright: createStyle(103, 49),
    blueBright: createStyle(104, 49),
    magentaBright: createStyle(105, 49),
    cyanBright: createStyle(106, 49),
    whiteBright: createStyle(107, 49),
  };
  /**
   * All start codes.
   */
  let starts: IntSet.t =
    IntSet.of_list([
      1,
      2,
      3,
      4,
      7,
      8,
      9,
      /* colors */
      30,
      31,
      32,
      33,
      34,
      35,
      36,
      37,
      90,
      91,
      92,
      93,
      94,
      95,
      96,
      97,
      /* bg colors */
      40,
      41,
      42,
      43,
      44,
      45,
      46,
      100,
      101,
      102,
      103,
      104,
      105,
      106,
      107,
    ]);
  /**
   * All stop codes.
   */
  let stops: IntSet.t = IntSet.of_list([0, 22, 23, 24, 27, 28, 29, 39, 49]);
  /**
   * This is a mapping of stopCode => set of startCodes that use that stopCode.
   *
   * This can be helpful for determining whether or not a particular startCode is
   * still affecting a part of the string when manually parsing the string.
   */
  let stopToStarts: IntMap.t(IntSet.t) =
    IntMap.empty
    |> IntMap.add(0, starts)
    |> IntMap.add(22, IntSet.of_list([1, 2]))
    |> IntMap.add(23, IntSet.of_list([3]))
    |> IntMap.add(24, IntSet.of_list([4]))
    |> IntMap.add(27, IntSet.of_list([7]))
    |> IntMap.add(28, IntSet.of_list([8]))
    |> IntMap.add(29, IntSet.of_list([9]))
    |> IntMap.add(
         39,
         IntSet.of_list([
           30,
           31,
           32,
           33,
           34,
           35,
           36,
           37,
           90,
           91,
           92,
           93,
           94,
           95,
           96,
           97,
         ]),
       )
    |> IntMap.add(
         49,
         IntSet.of_list([
           40,
           41,
           42,
           43,
           44,
           45,
           46,
           100,
           101,
           102,
           103,
           104,
           105,
           106,
           107,
         ]),
       );
};

type chalker = string => string;

type part = {
  value: string,
  isModifier: bool,
  modifiers: IntSet.t,
};

let escapeCodeRegex = {
  let start = "\027\\[";
  let codesStart = "\\(";
  let codesList = IntSet.elements(Ansi.starts) @ IntSet.elements(Ansi.stops);
  let codesMiddle =
    List.fold_left(
      ~f=(s, code) => s ++ "\\|" ++ string_of_int(code),
      ~init=string_of_int(List.hd(codesList)),
      List.tl(codesList),
    );
  let codesStop = "\\)";
  let stop = "m";
  let regexString = start ++ codesStart ++ codesMiddle ++ codesStop ++ stop;
  Str.regexp(regexString);
};

let nonDigitRegex = Str.regexp("[^0-9]");

let parseString = (s: string): list(part) => {
  let parts = Str.full_split(escapeCodeRegex, s);
  let (parts, _) =
    parts
    |> List.fold_left(
         ~f=
           ((result, modifiers), part) =>
             switch (part) {
             | Str.Text(value) => (
                 result @ [{value, modifiers, isModifier: false}],
                 modifiers,
               )
             | Str.Delim(value) =>
               let codeString = Str.global_replace(nonDigitRegex, "", value);
               let code = int_of_string(codeString);
               let modifiers =
                 if (IntSet.mem(code, Ansi.starts)) {
                   IntSet.add(code, modifiers);
                 } else if (IntSet.mem(code, Ansi.stops)) {
                   let startsToRemove = IntMap.find(code, Ansi.stopToStarts);
                   IntSet.filter(
                     code => !IntSet.mem(code, startsToRemove),
                     modifiers,
                   );
                 } else {
                   failwith(
                     "Unknown escape code matched escapeCodeRegex: "
                     ++ codeString,
                   );
                 };
               (result @ [{value, modifiers, isModifier: true}], modifiers);
             },
         ~init=([], IntSet.empty),
       );
  parts;
};

let createChalker = (style: Ansi.style): chalker => {
  let chalker = (s: string) => {
    let parts = parseString(s);
    /* Now we apply the style to all parts with non-conflicting modifiers */
    List.fold_left(
      ~f=
        (result, part) =>
          if (part.isModifier) {
            result ++ part.value;
          } else {
            let myStopCode = style.stopCode;
            let conflictingStarts =
              IntMap.find(myStopCode, Ansi.stopToStarts);
            let next =
              if (IntSet.exists(
                    code => IntSet.mem(code, conflictingStarts),
                    part.modifiers,
                  )) {
                part.value;
              } else {
                style.start ++ part.value ++ style.stop;
              };
            result ++ next;
          },
      ~init="",
      parts,
    );
  };
  chalker;
};

type modifier = {
  bold: chalker,
  dim: chalker,
  italic: chalker,
  underline: chalker,
  inverse: chalker,
  hidden: chalker,
  strikethrough: chalker,
};

type color = {
  black: chalker,
  red: chalker,
  green: chalker,
  yellow: chalker,
  blue: chalker,
  magenta: chalker,
  cyan: chalker,
  white: chalker,
  gray: chalker,
  grey: chalker,
  redBright: chalker,
  greenBright: chalker,
  yellowBright: chalker,
  blueBright: chalker,
  magentaBright: chalker,
  cyanBright: chalker,
  whiteBright: chalker,
};

type bg = {
  black: chalker,
  red: chalker,
  green: chalker,
  yellow: chalker,
  blue: chalker,
  magenta: chalker,
  cyan: chalker,
  white: chalker,
  blackBright: chalker,
  redBright: chalker,
  greenBright: chalker,
  yellowBright: chalker,
  blueBright: chalker,
  magentaBright: chalker,
  cyanBright: chalker,
  whiteBright: chalker,
};

let modifier: modifier = {
  bold: createChalker(Ansi.modifier.bold),
  dim: createChalker(Ansi.modifier.dim),
  italic: createChalker(Ansi.modifier.italic),
  underline: createChalker(Ansi.modifier.underline),
  inverse: createChalker(Ansi.modifier.inverse),
  hidden: createChalker(Ansi.modifier.hidden),
  strikethrough: createChalker(Ansi.modifier.strikethrough),
};

let bold = modifier.bold;

let dim = modifier.dim;

let italic = modifier.italic;

let underline = modifier.underline;

let inverse = modifier.inverse;

let hidden = modifier.hidden;

let strikethrough = modifier.strikethrough;

let color: color = {
  black: createChalker(Ansi.color.black),
  red: createChalker(Ansi.color.red),
  green: createChalker(Ansi.color.green),
  yellow: createChalker(Ansi.color.yellow),
  blue: createChalker(Ansi.color.blue),
  magenta: createChalker(Ansi.color.magenta),
  cyan: createChalker(Ansi.color.cyan),
  white: createChalker(Ansi.color.white),
  gray: createChalker(Ansi.color.gray),
  grey: createChalker(Ansi.color.grey),
  redBright: createChalker(Ansi.color.redBright),
  greenBright: createChalker(Ansi.color.greenBright),
  yellowBright: createChalker(Ansi.color.yellowBright),
  blueBright: createChalker(Ansi.color.blueBright),
  magentaBright: createChalker(Ansi.color.magentaBright),
  cyanBright: createChalker(Ansi.color.cyanBright),
  whiteBright: createChalker(Ansi.color.whiteBright),
};

let black = color.black;

let red = color.red;

let green = color.green;

let yellow = color.yellow;

let blue = color.blue;

let magenta = color.magenta;

let cyan = color.cyan;

let white = color.white;

let gray = color.gray;

let grey = color.grey;

let redBright = color.redBright;

let greenBright = color.greenBright;

let yellowBright = color.yellowBright;

let blueBright = color.blueBright;

let magentaBright = color.magentaBright;

let cyanBright = color.cyanBright;

let whiteBright = color.whiteBright;

let bg: bg = {
  black: createChalker(Ansi.bg.black),
  red: createChalker(Ansi.bg.red),
  green: createChalker(Ansi.bg.green),
  yellow: createChalker(Ansi.bg.yellow),
  blue: createChalker(Ansi.bg.blue),
  magenta: createChalker(Ansi.bg.magenta),
  cyan: createChalker(Ansi.bg.cyan),
  white: createChalker(Ansi.bg.white),
  blackBright: createChalker(Ansi.bg.blackBright),
  redBright: createChalker(Ansi.bg.redBright),
  greenBright: createChalker(Ansi.bg.greenBright),
  yellowBright: createChalker(Ansi.bg.yellowBright),
  blueBright: createChalker(Ansi.bg.blueBright),
  magentaBright: createChalker(Ansi.bg.magentaBright),
  cyanBright: createChalker(Ansi.bg.cyanBright),
  whiteBright: createChalker(Ansi.bg.whiteBright),
};
