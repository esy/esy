/* Utils for manipulating terminal output */
let resetANSI = "\027[0m";

let boldCode = b => b ? "\027[1m" : "";

let dimCode = d => d ? "\027[2m" : "";

let underlineCode = u => u ? "\027[4m" : "";

let bold = s => boldCode(true) ++ s ++ resetANSI;

let dim = s => dimCode(true) ++ s ++ resetANSI;

let underline = s => underlineCode(true) ++ s ++ resetANSI;

let redCode = "\027[31m";

let greenCode = "\027[32m";

let yellowCode = "\027[33m";

let blueCode = "\027[34m";

let magentaCode = "\027[35m";

let cyanCode = "\027[36m";

let whiteCode = "\027[37m";

let greyCode = "\027[90m";

let styled = (~bold=false, ~dim=false, ~underline=false, str) =>
  boldCode(bold)
  ++ dimCode(dim)
  ++ underlineCode(underline)
  ++ str
  ++ resetANSI;

let red = (~bold=false, ~dim=false, ~underline=false, str) =>
  styled(~bold, ~dim, ~underline, redCode ++ str);

let green = (~bold=false, ~dim=false, ~underline=false, str) =>
  styled(~bold, ~dim, ~underline, greenCode ++ str);

let yellow = (~bold=false, ~dim=false, ~underline=false, str) =>
  styled(~bold, ~dim, ~underline, yellowCode ++ str);

let blue = (~bold=false, ~dim=false, ~underline=false, str) =>
  styled(~bold, ~dim, ~underline, blueCode ++ str);

let cyan = (~bold=false, ~dim=false, ~underline=false, str) =>
  styled(~bold, ~dim, ~underline, cyanCode ++ str);

let grey = (~bold=false, ~dim=false, ~underline=false, str) =>
  styled(~bold, ~dim, ~underline, greyCode ++ str);

let highlight = (~color=red, ~bold=false, ~dim=false, ~underline=false, str) =>
  color(~bold, ~dim, ~underline, str);