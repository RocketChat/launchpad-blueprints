#!/bin/bash
# images.sh lists all images used by launchpad. An optional 'download' argument saves 
# the images locally (docker save).
#
# It uses our chartcontents.sh to list chart images.
#
# yq (https://github.com/mikefarah/yq) is required.
# docker (https://docs.docker.com/engine/install/) is required.

if ! command -v yq &> /dev/null; then
    echo "'yq' is required but not found" >&2
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "'docker' is required but not found" >&2
    exit 1
fi

if [ -z "$1" ]; then
	echo "Usage: $0 rocketchat-tag"
	exit 1
fi

rocketchat_tag=$1

bash ./bin/chartcontents.sh "manifests/v1alpha1/*/*-helmchart.yaml"

images="$(yq -N '.spec.template.spec.containers[].image' manifests/v1alpha1/launchcontrol/* manifests/v1alpha1/airlock/* manifests/v1alpha1/helm-controller/*)
"

images+="$(yq -N '.spec.containers[].image' manifests/v1alpha1/mongosh/*)
"

images+="$(cat offline/charts/*.images)
"

images+="
rocketchat/account-service:${rocketchat_tag}
rocketchat/authorization-service:${rocketchat_tag}
rocketchat/ddp-streamer-service:${rocketchat_tag}
rocketchat/omnichannel-transcript-service:${rocketchat_tag}
rocketchat/presence-service:${rocketchat_tag}
rocketchat/queue-worker-service:${rocketchat_tag}
rocketchat/rocket.chat:${rocketchat_tag}
rocketchat/stream-hub-service:${rocketchat_tag}
"

images+="$(curl -s https://raw.githubusercontent.com/longhorn/longhorn/v1.10.1/deploy/longhorn-images.txt)"

# these are hidden in launchcontrol and mongo operators
images+="
nats:2.4.0-alpine
natsio/prometheus-nats-exporter:0.9.3
natsio/nats-server-config-reloader:0.14.1
docker.io/mongodb/mongodb-community-server:8.0.14-ubi8
quay.io/mongodb/mongodb-kubernetes-operator-version-upgrade-post-start-hook:1.0.10
quay.io/mongodb/mongodb-agent-ubi:108.0.6.8796-1
docker.io/grafana/grafana:11.3.0
docker.io/traefik/whoami:latest
"

images=$(sort <<< $images | uniq)

cat <<< $images
