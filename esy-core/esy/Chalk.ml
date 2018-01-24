(**
 * Utils for manipulating terminal output
 *)

let resetANSI = "\027[0m"

let boldCode = function
  | true  -> "\027[1m"
  | false  -> ""
let dimCode = function
  | true  -> "\027[2m"
  | false  -> ""
let underlineCode = function
  | true  -> "\027[4m"
  | false  -> ""

let bold s = (boldCode true) ^ s ^ resetANSI
let dim s = (dimCode true) ^ s ^ resetANSI
let underline s = (underlineCode true) ^ s ^ resetANSI

let redCode = "\027[31m"
let greenCode = "\027[32m"
let yellowCode = "\027[33m"
let blueCode = "\027[34m"
let magentaCode = "\027[35m"
let cyanCode = "\027[36m"
let whiteCode = "\027[37m"
let greyCode = "\027[90m"

let styled ?(bold=false) ?(dim=false) ?(underline=false) () =
  (boldCode bold) ^ (dimCode dim) ^ (underlineCode underline)

let red ?(bold=false) ?(dim=false) ?(underline=false) s =
  (styled ~bold ~dim ~underline ()) ^ redCode ^ s ^ resetANSI
let green ?(bold= false) ?(dim=false) ?(underline= false) s =
  (styled ~bold ~dim ~underline ()) ^ greenCode ^ s ^ resetANSI
let yellow ?(bold= false) ?(dim=false) ?(underline= false) s =
  (styled ~bold ~dim ~underline ()) ^ yellowCode ^ s ^ resetANSI
let blue ?(bold= false) ?(dim=false) ?(underline= false) s =
  (styled ~bold ~dim ~underline ()) ^ blueCode ^ s ^ resetANSI
let cyan ?(bold= false) ?(dim=false) ?(underline= false) s =
  (styled ~bold ~dim ~underline ()) ^ cyanCode ^ s ^ resetANSI
let grey ?(bold= false) ?(dim=false) ?(underline=false) s =
  (styled ~bold ~dim ~underline ()) ^ greyCode ^ s ^ resetANSI

let highlight ?(color=red) ?(bold=false) ?(dim=false) ?(underline=false) str =
  color ~bold ~dim ~underline str