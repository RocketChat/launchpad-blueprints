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
node_memory=2048
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

	node_ip="@"

	while ! ssh -o "StrictHostKeyChecking no" -i $user_ssh_key ${ssh_user}@${node_ip} 'uname -a'; do
		ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$node_ip"
		node_ip=$(sudo virsh domifaddr "$node" | grep ipv4 | awk '{print $4}' | cut -f1 -d'/')
                sleep 1
        done

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
	#--install-env INSTALL_K3S_EXEC="--disable=traefik"

KUBECONFIG="$HOME/.autok3s/.kube/config" kubectl config view --minify --flatten > "${wrk}/${cluster}.kubeconfig"

echo "done. run KUBECONFIG="${wrk}/${cluster}.kubeconfig" kubectl get nodes"
echo
echo "if using dnsmasq, add to /etc/dnsmasq.conf:"
echo "address=/.${cluster}.local/${master}"
echo "then sudo systemctl restart dnsmasq"

