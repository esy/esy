[@deriving (to_yojson, of_yojson({strict: false}))]
type t = {
  checksum: Checksum.t,
  url: string,
  relativePath: string,
};
