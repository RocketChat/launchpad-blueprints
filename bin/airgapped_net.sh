#!/bin/bash
#
# airgapped_net.sh creates a network for simulating air-gapped environments.
# The configuration allows host-to-VMs and VM-to-VM communication.
#

# configuration
NET_NAME="airgapped-net"
BRIDGE_NAME="virbr2"     # Ensure this doesn't conflict with existing bridges (virbr0 is default)
SUBNET_IP="192.168.100.1"
NETMASK="255.255.255.0"
DHCP_START="192.168.100.2"
DHCP_END="192.168.100.254"
#


check_error() {
    if [ $? -ne 0 ]; then
        echo "Error: $1"
        exit 1
    fi
}

if virsh net-info $NET_NAME > /dev/null 2>&1; then
    echo "Network '$NET_NAME' already exists."
    
    if virsh net-list --all | grep $NET_NAME | grep -q "active"; then
        echo "Network is already active."
    else
        echo "Starting existing network..."
        virsh net-start $NET_NAME
    fi
    exit 0
fi

TEMP_XML="/tmp/${NET_NAME}.xml"

cat > $TEMP_XML <<EOF
<network>
  <name>$NET_NAME</name>
  <bridge name='$BRIDGE_NAME' stp='on' delay='0'/>
  <domain name='isolated.local'/>
  <ip address='$SUBNET_IP' netmask='$NETMASK'>
    <dhcp>
      <range start='$DHCP_START' end='$DHCP_END'/>
    </dhcp>
  </ip>
</network>
EOF

echo "Defining network from $TEMP_XML ..."
virsh net-define $TEMP_XML
check_error "Failed to define network."

echo "Starting network $NET_NAME  ..."
virsh net-start $NET_NAME
check_error "Failed to start network."

echo "Enabling autostart..."
virsh net-autostart $NET_NAME
check_error "Failed to enable autostart."

virsh net-list --all | grep $NET_NAME
echo "Network '$NET_NAME' is ready."
echo "Host IP on bridge: $SUBNET_IP"
echo "VMs will receive IPs in range: $DHCP_START - $DHCP_END"

rm -f $TEMP_XML
