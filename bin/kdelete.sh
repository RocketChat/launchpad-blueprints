#!/bin/bash
#
# kdelete.sh cleans up a setup made by cluster-create.sh .
#
# KVM, libvirt and cloud-init utilities are required:
#   sudo apt update && sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst cloud-image-utils

# configuration: start
#
# wrk is where we contain the setup
wrk=~/kvm-lab
#
# configuration: end

if [ $# -ne 1 ]; then
        echo "Usage: $0 cluster-name"
        echo "Example: $0 my-lab"
        exit
fi

for d in "virsh"; do
        if ! command -v $d &> /dev/null; then
          echo "'${d}' is required but not found" >&2
          exit 1
        fi
done

cluster="$1"

if [ ! -d "${wrk}/$cluster" ]; then
        echo "$cluster doesn't exist - won't operate"
        exit 1
fi

nodes=$(virsh list --all | grep "${cluster}-node-" | awk '{print $2}')

if [ -z "$nodes" ]; then
	echo "could not find a node. nodes:"
	virsh list
	exit 1
fi

for n in $nodes; do
	virsh undefine $n
	virsh destroy $n
done

rm -rv "${wrk}/${cluster}" "${wrk}/${cluster}.kubeconfig"

