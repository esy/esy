(**
 * Build task.
 *
 * TODO: Reconcile with EsyLib.BuildTask, right now we just reuse types & code
 * from there but it probably should live here instead. Fix that after we decide
 * on better package boundaries.
 *)

type t = EsyLib.BuildTask.t

let pp = EsyLib.BuildTask.pp
let show = EsyLib.BuildTask.show

type buildType = EsyLib.BuildTask.buildType

let pp_buildType = EsyLib.BuildTask.pp_buildType
let show_buildType = EsyLib.BuildTask.show_buildType

type sourceType = EsyLib.BuildTask.sourceType

let pp_sourceType = EsyLib.BuildTask.pp_sourceType
let show_sourceType = EsyLib.BuildTask.show_sourceType

let ofPackage (pkg : Package.t) =
  let f ~allDependencies:_ ~dependencies:_ (pkg : Package.t) =
    print_endline pkg.id
  in
  Package.fold ~f pkg
