#!/bin/bash
#
# switch_network_static.sh switches a Libvirt VM network AND configures persistent Static IP
# via Cloud-Init (config-drive).
# It is used by k3s_cluster_create.sh
#
# Requires: cloud-image-utils, virsh
#

# where to store the generated ISO files
wrk=~/kvm-lab
#


if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <vm_name> <new_network_name> <ip_address_cidr> [gateway_ip]"
    echo "Example: $0 constrained-vm airgapped-net 192.168.100.5/24 192.168.100.1"
    exit 1
fi

VM_NAME=$1
NEW_NET=$2
NEW_IP=$3
GATEWAY=$4


ISO_DIR="${wrk}/${VM_NAME}"
mkdir -p "$ISO_DIR"
ISO_PATH="$ISO_DIR/${VM_NAME}-network-config.iso"

if ! command -v cloud-localds &> /dev/null; then
    echo "Error: 'cloud-localds' is not installed."
    echo "Please run: sudo apt install cloud-image-utils"
    exit 1
fi

MAC_ADDR=$(virsh domiflist $VM_NAME | grep -m 1 -E "network|bridge" | awk '{print $5}')

if [ -z "$MAC_ADDR" ]; then
    echo "Error: Could not find a network interface on VM '$VM_NAME'."
    exit 1
fi

TEMP_XML="/tmp/net_switch_${VM_NAME}.xml"

cat > $TEMP_XML <<EOF
<interface type='network'>
  <mac address='$MAC_ADDR'/>
  <source network='$NEW_NET'/>
  <model type='virtio'/>
</interface>
EOF

echo "Switching VM network connection to '$NEW_NET'..."

if ! virsh update-device $VM_NAME $TEMP_XML --live --config; then
    echo "Error: Failed to switch network."
    exit 1
fi

rm -f $TEMP_XML

cat > "network-config" <<EOF
version: 2
ethernets:
  id0:
    match:
      macaddress: "$MAC_ADDR"
    addresses:
      - $NEW_IP
EOF

if [ -n "$GATEWAY" ]; then
    cat >> "network-config" <<EOF
    gateway4: $GATEWAY
EOF
fi

cat >> "network-config" <<EOF
    nameservers:
      addresses: [8.8.8.8, 1.1.1.1]
EOF

# dummy meta-data (required by cloud-localds)
echo "instance-id: $(uuidgen || echo i-custom)" > meta-data

echo "Building config drive at $ISO_PATH..."

if ! cloud-localds -v --network-config network-config "$ISO_PATH" meta-data; then
    echo "Error: Failed to create ISO."
    exit 1
fi

rm -f network-config meta-data

TARGET_DISK="vdb"

# in case vdb is already taken...
if virsh domblklist $VM_NAME | grep -q "$TARGET_DISK"; then
    echo "Warning: $TARGET_DISK seems to be in use. Trying 'vdc'..."
    TARGET_DISK="vdc"
fi

echo "Attaching configuration drive to $TARGET_DISK..."

if ! virsh attach-disk $VM_NAME "$ISO_PATH" $TARGET_DISK --driver qemu --subdriver raw --type disk --mode readonly --live --config; then
    echo "Error: Failed to attach disk. Check if $TARGET_DISK is free."
    exit 1
fi

echo "'$VM_NAME' will be configured with the static IP '$NEW_IP' after reboot."
