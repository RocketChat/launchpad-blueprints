#!/bin/bash
# imsave.sh saves images locally (docker save).
#
# docker (https://docs.docker.com/engine/install/) is required.

if ! command -v docker &> /dev/null; then
    echo "'docker' is required but not found" >&2
    exit 1
fi

images=$(</dev/stdin)
images=$(sort <<< $images | uniq)

d="./offline/images"

mkdir -pv "$d"

for im in $images; do
	tar="${d}/$(basename $im).tar"

	if [ -f "${tar}" ]; then
		echo "skipping $tar"
		continue
	fi

	echo P: $im

	docker pull $im -q
	docker save $im -o "$tar" > /dev/null
	docker image rm $im > /dev/null
done

