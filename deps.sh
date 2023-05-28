read -a esy_dirs <<< $(find  . -name 'esy-*' -type d -not -path './_build'  -not -path './_esy')
flags=""
for dir in "${esy_dirs[@]}";
do
    flags="$flags -I $dir"
done

sources=""
for dir in "${esy_dirs[@]}";
do
    sources="${sources} ${dir}/*.re"
done

ocamldep $flags -pp 'refmt --print binary' $sources -ml-synonym '.re' > .depends
     #  ocamldepdot -fullgraph  > dep.dot
