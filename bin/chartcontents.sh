#!/bin/bash
#
# chartcontents.sh standardizes chart assets extraction (contents and images used). It fetches
# our chart contents and also extract images used (read by our images.sh).
#
# An optional 'patch' argument patches our HelmChart CRDs '.spec.chartContent' with the
# base64 encoded content. More at https://github.com/k3s-io/helm-controller/blob/master/doc/helmchart.md#helmchartspec
#
# yq (https://github.com/mikefarah/yq) is required.
# helm (https://helm.sh/docs/intro/install/) is required.
# helm images plugin (https://github.com/nikhilsbhat/helm-images) is required (auto installed if not present).

IFS='
'

charts=$(ls manifests/v1alpha1/*/*-helmchart.yaml)

if ! command -v helm &> /dev/null; then
    echo "'helm' is required but not found" >&2
    exit 1
fi

try=$(helm images &> /dev/null); if [ $? -eq 1 ]; then
	helm plugin install https://github.com/nikhilsbhat/helm-images
fi

if ! command -v yq &> /dev/null; then
    echo "'yq' is required but not found" >&2
    exit 1
fi

if [ "$1" = "patch" ]; then
        patch="true"
fi

if [ -d ./offline/charts ]; then
	rm -v offline/charts/*
else
	mkdir -pv offline/charts
fi

for c in $charts; do
	repo="$(yq '.spec.repo' < $c)"
	chart="$(yq '.spec.chart' < $c)"
	version="$(yq '.spec.version' < $c)"

	echo "helm pull --repo ${repo} ${chart} --version ${version} -d ./offline/charts"
	helm pull --repo ${repo} ${chart} --version ${version} -d ./offline/charts

	helm images get ./offline/charts/${chart}-*.tgz > ./offline/charts/${chart}.images

	if [ -n "$patch" ]; then
		base64 -w0 ./offline/charts/${chart}-*.tgz > ./offline/charts/${chart}.b64
		yq -i ".spec.chartContent = load_str(\"./offline/charts/${chart}.b64\")" $c
	fi
done

