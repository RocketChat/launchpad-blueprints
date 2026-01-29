#!/bin/bash
#
# kimload.sh imports images directly into K3s containerd image store 
# by placing image tarballs in the /var/lib/rancher/k3s/agent/images directory.
# More at https://docs.k3s.io/add-ons/import-images?import-images=Offline+image+importing
# It expects a cluster created with kcreate.sh .
#

# node's ssh config
ssh_user="ubuntu"
user_ssh_key=~/.ssh/kvm_lab_rsa
#

if [ $# -lt 2 ]; then
        echo "Usage: $0 cluster image1 [... imageN]"
        echo "Example: $0 my-lab offline/images/mongo\:4.4.2.tar"
        exit
fi

for d in "virsh ssh"; do
        if ! command -v $d &> /dev/null; then
          echo "'${d}' is required but not found" >&2
          exit 1
        fi
done

cluster="$1"
images=${@:2}

nodes=$(virsh list | grep "${cluster}-node-" | awk '{print $2}')

for node in $nodes; do
	node_ip=$(virsh domifaddr "$node" --source agent | grep enp1s0 | awk '{print $4}' | cut -f1 -d'/')

	ssh -o "StrictHostKeyChecking no" -i "$user_ssh_key" "${ssh_user}@${node_ip}" 'uname -a'
	[[ $? -ne 0 ]] && exit 1

	ssh -i "$user_ssh_key" "${ssh_user}@${node_ip}" \
		"sudo mkdir -pv /var/lib/rancher/k3s/agent/images && mkdir -pv /home/${ssh_user}/images/"

	scp -r -i "$user_ssh_key" $images "${ssh_user}@${node_ip}:/home/${ssh_user}/images/"

	ssh -i "$user_ssh_key" "${ssh_user}@${node_ip}" \
		"sudo mv -v /home/${ssh_user}/images/* /var/lib/rancher/k3s/agent/images/"
done
