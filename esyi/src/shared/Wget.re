
let get = url => {
  let (lines, good) = ExecCommand.execSync(~cmd="curl -s -f -L " ++ url, ());
  if (good) {
    Some(String.concat("\n", lines))
  } else {
    None
  }
}