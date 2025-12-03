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
# k3s is the exec K3s binary [also images] (scp, speed up)
# https://github.com/k3s-io/k3s/releases
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
node_disk_size="30G"
node_network="default"
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
	echo "$cluster exists - won't operate. can 'cluster-delete.sh ${cluster}'"
	exit 1
fi

mkdir -pv "${wrk}/$cluster"
	
for n in $(seq 1 "$size"); do
	node="${cluster}-node-${n}"

	init="${wrk}/${cluster}/${node}-cloud-init"

	cat > $init <<EOF
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
#package_update: true
packages:
  - qemu-guest-agent # Important for libvirt to see IP addresses
  - open-iscsi # https://longhorn.io/docs/1.10.1/deploy/install/#installing-open-iscsi
runcmd:
  - systemctl restart ssh
  - echo "Node is ready!"
EOF

	disk="${wrk}/${cluster}/${node}-disk.qcow2"
	cp "$baseimage" "$disk"
	qemu-img resize "$disk" "+${node_disk_size}"

	sudo virt-install   \
		--name "$node"   \
		--memory "$node_memory"   \
		--vcpus "$node_vcpus"   \
		--disk path="${disk}",device=disk,bus=virtio \
	      	--os-variant "$os_variant"    \
		--network "network=${node_network},model=virtio"   \
		--graphics none   \
		--import   \
		--noautoconsole   \
		--cloud-init user-data="${init}"

	echo "waiting for $node ..."

	while :; do
		node_ip=$(sudo virsh domifaddr "$node" | grep ipv4 | awk '{print $4}' | cut -f1 -d'/')
		ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$node_ip"

		ssh -o "StrictHostKeyChecking no" -i "$user_ssh_key" "${ssh_user}@${node_ip}" 'uname -a'
		([[ $? -ne 0 ]] && sleep 1) || break
	done

	scp -i "$user_ssh_key" "$k3s" "${ssh_user}@${node_ip}:/home/${ssh_user}/k3s"
	ssh -i "$user_ssh_key" "${ssh_user}@${node_ip}" "sudo mv /home/${ssh_user}/k3s /usr/local/bin/"

	# https://docs.k3s.io/installation/airgap?airgap-load-images=Manually+Deploy+Images#1-load-images
	scp -i "$user_ssh_key" "$k3s_images"  "${ssh_user}@${node_ip}:/home/${ssh_user}/"
	im=$(basename "$k3s_images"); ssh -i "$user_ssh_key" "${ssh_user}@${node_ip}" \
		"sudo mkdir -pv /var/lib/rancher/k3s/agent/images && sudo mv /home/${ssh_user}/${im} /var/lib/rancher/k3s/agent/images/"

	# https://docs.k3s.io/installation/packaged-components#using-skip-files
	ssh -i "$user_ssh_key" "${ssh_user}@${node_ip}" \
		"sudo mkdir -pv /var/lib/rancher/k3s/server/manifests && sudo touch /var/lib/rancher/k3s/server/manifests/traefik.yaml.skip"

	node_ips+=$node_ip
	if [ "$n" -ne "$size" ]; then
		node_ips+=","
	fi

	echo $node_ip > "${wrk}/${cluster}/${node}-ip"
done

cat <<< $node_ips

master=$(echo $node_ips | cut -f1 -d',')
workers=$(echo $node_ips | cut -f2- -d',')

autok3s -d create     \
	--provider native     \
	--name "$cluster"     \
	--ssh-user "$ssh_user"     \
	--ssh-key-path "$user_ssh_key"     \
	--master-ips "$master" \
	--worker-ips "$workers" \
	--install-env INSTALL_K3S_SKIP_DOWNLOAD=true

KUBECONFIG="$HOME/.autok3s/.kube/config" kubectl config view --minify --flatten > "${wrk}/${cluster}.kubeconfig"

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

