#!/bin/bash
#
# rename.sh standardizes configuration names based on their content (name and type).
# It is ready to parse output from https://github.com/komish/yamlsplit (or a set of
# n.yaml files, where 'n' is a number).
#
# yq (https://github.com/mikefarah/yq) is required.

IFS='
'

for y in $(ls *.yaml | sort -V); do
	n=$(basename $y .yaml) # n.yaml -> n
	n=$(printf "%02d" $n)  # 2 width, pad with 0

	name=$(cat $y | yq .metadata.name)
	kind=$(cat $y | yq .kind | tr [A-Z] [a-z])

	filename="$n-$name-$kind.yaml"

	mv -v $y $filename
done
