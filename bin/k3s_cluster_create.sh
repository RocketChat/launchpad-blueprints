#!/bin/bash
#
# cluster-create.sh launches a new K3s cluster on virtual 'nodes'.
# Please review and define your cluster-create.config .
#
# For simplicity, the first node created will be the single K8s master.
#
# KVM, libvirt and cloud-init utilities are required:
#   sudo apt update && sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst cloud-image-utils
# autok3s (https://github.com/cnrancher/autok3s/releases) is required.


# configuration: start
#
# wrk is where we contain the setup
wrk=~/kvm-lab
#
# if not empty, we switch cluster to air_gapped_network after setting up node host
# but before installing K3s. Cluster should behave as offline after install.
# air_gapped_network will be created with create_airgapped_net.sh (check config).
air_gapped_network="" # "airgapped-net"
air_gapped_subnet_ip="192.168.100.1"
#
# k3s assets (scp, speed up)
#   - install script: https://get.k3s.io/
#   - binary, images: https://github.com/k3s-io/k3s/releases
k3s_install="${wrk}/k3s-releases/install.sh"
k3s="${wrk}/k3s-releases/k3s"
k3s_images="${wrk}/k3s-releases/k3s-airgap-images-amd64.tar.gz"
#
# baseimage is the KVM, bootable OS cloud image
# https://cloud-images.ubuntu.com/minimal/releases/jammy/release/
baseimage="${wrk}/baseimages/ubuntu-22.04-minimal-cloudimg-amd64.img"
#
# os_variant hints specific operating system configuration
# must be one of:
# $ virt-install --os-variant list
os_variant="ubuntu22.04"
#
# ssh_user is the default user with sudo privileges
ssh_user="ubuntu"
#
# user_ssh_key defines the pair to be used for installing k3s
# (and ssh in general); generate with ssh-keygen, no password
user_ssh_key=~/.ssh/kvm_lab_rsa
#
# nodes configuration
node_memory=4096
node_vcpus=2
node_disk_size="50G"
node_network="default"
node_network_subnet_ip="192.168.122.1"
#
# configuration: end

if [ $# -ne 2 ]; then
	echo "Usage: $0 cluster-name cluster-size"
	echo "Example: $0 my-lab 2"
	exit
fi

for d in "qemu-img virt-install virsh ssh ssh-keygen autok3s"; do
	if ! command -v $d &> /dev/null; then
  	  echo "'${d}' is required but not found" >&2
  	  exit 1
	fi
done

cluster="$1"
size="$2"

if [ "$size" -lt 2 ]; then
	size=2
fi

if [ -d "${wrk}/$cluster" ]; then
	echo "$cluster exists - won't operate. can 'k3s_cluster_delete.sh ${cluster}'"
	exit 1
fi

mkdir -pv "${wrk}/$cluster"
	
for n in $(seq 1 "$size"); do
	node="${cluster}-node-${n}"

	init_user="${wrk}/${cluster}/${node}-cloud-init-user"
	init_net="${wrk}/${cluster}/${node}-cloud-init-net"

	cat > $init_user <<EOF
#cloud-config
hostname: ${node}
fqdn: ${node}.local
manage_etc_hosts: true

users:
  - name: ${ssh_user}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat ${user_ssh_key}.pub)
ssh_pwauth: false
disable_root: false

package_update: false
packages: []
EOF

prefix="$(echo $node_network_subnet_ip | cut -f1-3 -d'.')"
node_ip="${prefix}.$((n + 1))"

        cat > $init_net <<EOF
version: 2
ethernets:
  id0:
    match:
      name: "en*"
    addresses:
      - ${node_ip}/24
    gateway4: ${node_network_subnet_ip}
    nameservers:
      addresses: [8.8.8.8, 1.1.1.1]
EOF

	disk="${wrk}/${cluster}/${node}-disk.qcow2"
	cp "$baseimage" "$disk"
	qemu-img resize "$disk" "+${node_disk_size}"

	virt-install   \
		--name "$node"   \
		--memory "$node_memory"   \
		--vcpus "$node_vcpus"   \
		--disk path="${disk}",device=disk,bus=virtio,cache=none \
	      	--os-variant "$os_variant"    \
		--network "network=${node_network},model=virtio"   \
		--graphics none   \
		--import   \
		--noautoconsole   \
		--cloud-init user-data=${init_user},network-config=${init_net} \
		--channel unix,target_type=virtio,name=org.qemu.guest_agent.0

	echo "waiting for $node ..."

	while :; do
                ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$node_ip" 2> /dev/null
                ssh -o "StrictHostKeyChecking no" -i "$user_ssh_key" "${ssh_user}@${node_ip}" 'uname -a && cloud-init status --wait' 2> /dev/null
                ([[ $? -ne 0 ]] && sleep 1) || break
        done

	# install online deps (qemu guest and longhorn)
	# https://longhorn.io/docs/1.10.1/deploy/install/#installing-open-iscsi
	ssh -i "$user_ssh_key" "${ssh_user}@${node_ip}" "sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf; \
		until sudo resolvectl status && sudo apt-get update; do sleep 2; done; \
		DEBIAN_FRONTEND=noninteractive sudo apt-get install -y qemu-guest-agent open-iscsi dmsetup nfs-common cryptsetup && \
		sudo systemctl enable --now qemu-guest-agent"

	if [ -n "$air_gapped_network" ]; then
		./bin/create_airgapped_net.sh

		node_network="$air_gapped_network"
		node_network_subnet_ip="$air_gapped_subnet_ip"

		prefix="$(echo $node_network_subnet_ip | cut -f1-3 -d'.')"
		node_ip="${prefix}.$((n + 1))"

		./bin/switch_network_static.sh "$node" "$node_network" "${node_ip}/24" "$node_network_subnet_ip"

		virsh shutdown "$node" && sleep 10 && virsh start  "$node"
		
		while ! virsh qemu-agent-command "$node" '{"execute":"guest-ping"}' &> /dev/null; do
			sleep 1
		done

		ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$node_ip" 2> /dev/null
		ssh -o "StrictHostKeyChecking no" -i "$user_ssh_key" "${ssh_user}@${node_ip}" 'uname -a && cloud-init status --wait' 2> /dev/null
		[[ $? -eq 0 ]] || exit 1
	fi

	# copy k3s install script
	scp -i "$user_ssh_key" "$k3s_install" "${ssh_user}@${node_ip}:/home/${ssh_user}/install.sh"

	# copy k3s binary
	scp -i "$user_ssh_key" "$k3s" "${ssh_user}@${node_ip}:/home/${ssh_user}/k3s"
	ssh -i "$user_ssh_key" "${ssh_user}@${node_ip}" "sudo mv -v /home/${ssh_user}/k3s /usr/local/bin/"

	# copy k3s base images
	# https://docs.k3s.io/installation/airgap?airgap-load-images=Manually+Deploy+Images#1-load-images
	scp -i "$user_ssh_key" "$k3s_images"  "${ssh_user}@${node_ip}:/home/${ssh_user}/"
	im=$(basename "$k3s_images"); ssh -i "$user_ssh_key" "${ssh_user}@${node_ip}" \
		"sudo mkdir -pv /var/lib/rancher/k3s/agent/images && sudo mv -v /home/${ssh_user}/${im} /var/lib/rancher/k3s/agent/images/"

	# push local offline images
	g=./offline/images; if [ -d "$g" ] && [ -n "$air_gapped_network" ]; then
		scp -r -i "$user_ssh_key" "${g}" "${ssh_user}@${node_ip}:/home/${ssh_user}/images"
		ssh -i "$user_ssh_key" "${ssh_user}@${node_ip}" \
			"sudo mkdir -pv /var/lib/rancher/k3s/agent/images && sudo mv -v /home/${ssh_user}/images/* /var/lib/rancher/k3s/agent/images/"
	fi

	# K3s includes a built-in static file server. Any file you place in /var/lib/rancher/k3s/server/static/
        # on the control plane node becomes instantly accessible inside the cluster via the Kubernetes API URL.
	# There is a special "magic" variable in K3s Helm Controller: %{KUBERNETES_API}%.
	# Usage (HelmChart CRD): "spec.chart": "https://%{KUBERNETES_API}%/static/charts/my-app.tgz"
	c=./offline/charts; if [ $n -eq 1 ] && [ -d "$c" ] && [ -n "$air_gapped_network" ]; then
                scp -r -i "$user_ssh_key" "${c}" "${ssh_user}@${node_ip}:/home/${ssh_user}/charts"
                ssh -i "$user_ssh_key" "${ssh_user}@${node_ip}" \
                        "sudo mkdir -pv /var/lib/rancher/k3s/server/static/charts && sudo mv -v /home/${ssh_user}/charts/* /var/lib/rancher/k3s/server/static/charts/"
        fi

	# skip traefik and local-storage
	# https://docs.k3s.io/installation/packaged-components#using-skip-files
	ssh -i "$user_ssh_key" "${ssh_user}@${node_ip}" \
		"sudo mkdir -pv /var/lib/rancher/k3s/server/manifests && \
		sudo touch /var/lib/rancher/k3s/server/manifests/traefik.yaml.skip && \
		sudo touch /var/lib/rancher/k3s/server/manifests/local-storage.yaml.skip"

	node_ips+=$node_ip
	if [ "$n" -ne "$size" ]; then
		node_ips+=" "
	fi

	echo $node_ip > "${wrk}/${cluster}/${node}-ip"
done

cat <<< $node_ips

master=$(echo $node_ips | cut -f1 -d' ')
workers=$(echo $node_ips | cut -f2- -d' ')

tok="$(echo 'k3s-super-secret' | sha1sum | cut -f1 -d' ')"

# k3s master setup
ssh -i "$user_ssh_key" "${ssh_user}@${master}" "INSTALL_K3S_EXEC='server --advertise-address=${master} --cluster-cidr=10.42.0.0/16 --node-external-ip=${master} --tls-san=${master} ' INSTALL_K3S_SKIP_DOWNLOAD='true' K3S_TOKEN='${tok}' ./install.sh"

# k3s workers setup
for worker in $workers; do
	ssh -i "$user_ssh_key" "${ssh_user}@${worker}" "INSTALL_K3S_EXEC='--node-external-ip=${worker} ' INSTALL_K3S_SKIP_DOWNLOAD='true' K3S_TOKEN='${tok}' K3S_URL='https://${master}:6443' ./install.sh"
done

# grab kube config
ssh -i "$user_ssh_key" "${ssh_user}@${master}" "sudo cp /etc/rancher/k3s/k3s.yaml ${cluster}.kubeconfig && sudo chown ${ssh_user}:${ssh_user} ${cluster}.kubeconfig && chmod 600 ${cluster}.kubeconfig"
scp -i "$user_ssh_key" "${ssh_user}@${master}:/home/${ssh_user}/${cluster}.kubeconfig" "${wrk}/${cluster}.kubeconfig"
sed -i "s,server: https://127.0.0.1:6443,server: https://${master}:6443,g" "${wrk}/${cluster}.kubeconfig"

echo
echo "done. run KUBECONFIG="${wrk}/${cluster}.kubeconfig" kubectl get nodes"
echo
echo "if using dnsmasq, add to /etc/dnsmasq.conf:"
echo "address=/.${cluster}.local/${master}"
echo "then sudo systemctl restart dnsmasq"
echo
echo "you can ssh -i $user_ssh_key ${ssh_user}@${master} # or any of ${node_ips}"
echo
echo "have fun!"

