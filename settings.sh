#!/bin/bash

UNC="\033\0m"
RED="\033[31m"
BLUE="\033[34m"
GREEN="\033[32m"

echo -e "${BLUE}Script for network settings.${UNC}"


echo "   "

isp_settings() {
    echo -e "${GREEN}Executing settings for ISP machine.${UNC}"

    echo -e "${GREEN}Assigning name to the machine.${UNC}"
    hostnamectl set-hostname ISP

    echo -e "${GREEN}Creating directory for the adapter in the direction of SW1.${UNC}"
    mkdir /etc/net/ifaces/enp0s8

    echo -e "${GREEN}Filling the configuration file for the adapter in the direction of SW1.${UNC}"
    cat <<EOF > /etc/net/ifaces/enp0s8/options
TYPE=eth
BOOTPROTO=static
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
EOF

    echo -e "${GREEN}Assigning IP address to the interface${UNC}"
    echo "17.0.1.1/24" > /etc/net/ifaces/enp0s8/ipv4address
    echo -e "${GREEN}Enabling IP forwarding${UNC}"
    sed -i "s/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g" /etc/net/sysctl.conf
    echo "net.ipv4.conf.all.forwarding = 1" >> /etc/net/sysctl.conf
    systemctl restart network
    echo -e "${GREEN}Output of IP addresses for verification${UNC}"
    ip -c --br -4 a

    echo -e "${GREEN}Installing nftables to configure NAT (access to the network from other machines).${UNC}"
    echo -e "${GREEN}Changing /etc/resolv.conf for correct domain name resolution.${UNC}"
    echo "nameserver 77.88.8.8" > /etc/resolv.conf
    output=$(apt-get update && apt-get install -y nftables 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}nftables is installed.${UNC}"
    fi
    echo -e "${GREEN}Enabling nftables service.${UNC}"
    systemctl enable --now nftables
    echo -e "${GREEN}Integration of all necessary nftables rules and automatic saving.${UNC}"
    nft add table ip nat
    nft add chain ip nat postrouting '{ type nat hook postrouting priority 0; }'
    nft add rule ip nat postrouting ip saddr 17.0.1.0/24 oifname "enp0s3" counter masquerade
    nft add rule ip nat postrouting ip saddr 17.0.2.0/24 oifname "enp0s3" counter masquerade
    nft add rule ip nat postrouting ip saddr 17.0.3.0/24 oifname "enp0s3" counter masquerade
    nft add rule ip nat postrouting ip saddr 17.0.4.0/24 oifname "enp0s3" counter masquerade
    echo -e "${GREEN}Saving rules in /etc/nftables/nftables.nft.${UNC}"
    nft list ruleset | tail -n9 | tee -a /etc/nftables/nftables.nft
    echo -e "${GREEN}Restarting nftables service.${UNC}"
    systemctl restart nftables
    echo -e "${GREEN}Adding all necessary routes for the future.${UNC}"
    echo "17.0.2.0/24 via 17.0.1.2" >> /etc/net/ifaces/enp0s8/ipv4route
    echo "17.0.3.0/24 via 17.0.1.2" >> /etc/net/ifaces/enp0s8/ipv4route
    echo "17.0.4.0/24 via 17.0.1.2" >> /etc/net/ifaces/enp0s8/ipv4route
    echo -e "${GREEN}Setting is complete.${UNC}"
    echo -e "${GREEN}Dont forget to write 'exec bash' in the terminal.${UNC}"
}

sw1_settings() {
    echo -e "${GREEN}Executing settings for SW1 machine.${UNC}"

    echo -e "${GREEN}Assigning name to the machine.${UNC}"
    hostnamectl set-hostname sw1.test-kspsuti.ru

    echo -e "${GREEN}Temporary assignment of an IP address to the directing adapter enp0s3 towards ISP.${UNC}"
    ip addr add 17.0.1.2/24 dev enp0s3
    ip route add default via 17.0.1.1 dev enp0s3
    ip link set enp0s3 up

    echo -e "${GREEN}Installing Open vSwitch.${UNC}"
    echo -e "${GREEN}Changing /etc/resolv.conf for correct domain name resolution.${UNC}"
    echo "nameserver 77.88.8.8" > /etc/resolv.conf
    output=$(apt-get update && apt-get install -y openvswitch 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Open vSwitch installed.${UNC}"
    fi
    echo -e "${GREEN}Disabling deletion of special internal adapters created by Open vSwitch.${UNC}"
    sed -i "s/OVS_REMOVE=yes/OVS_REMOVE=no/g" /etc/net/ifaces/default/options
    echo -e "${GREEN}Enabling Open vSwitch permanently.${UNC}"
    systemctl enable --now openvswitch
    echo -e "${GREEN}Creating a bridge and adding all necessary adapters to it.${UNC}"
    ovs-vsctl add-br br0
    ovs-vsctl add-port br0 enp0s3
    ovs-vsctl add-port br0 enp0s8
    ovs-vsctl add-port br0 enp0s9
    echo -e "${GREEN}Checking added bridges and adapters.${UNC}"
    OVS_OUTPUT_SHOW=$(ovs-vsctl show 2>&1)
    ovs_check=false
    if ! grep -q "Bridge br0" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Bridge br0 not created.${UNC}"
    else
        echo -e "${GREEN}Bridge br0 created.${UNC}"
    fi
    if ! grep -q "Port enp0s3" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Adapter enp0s3 not added to bridge br0.${UNC}"
    else
        echo -e "${GREEN}Adapter enp0s3 added to bridge br0.${UNC}"
    fi
    if ! grep -q "Port enp0s8" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Adapter enp0s8 not added to bridge br0.${UNC}"
    else
        echo -e "${GREEN}Adapter enp0s8 added to bridge br0.${UNC}"
    fi
    if ! grep -q "Port enp0s9" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Adapter enp0s9 not added to bridge br0.${UNC}"
    else
        echo -e "${GREEN}Adapter enp0s9 added to bridge br0.${UNC}"
    fi
    if ! grep -q "Port br0" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Bridge br0 not integrated.${UNC}"
    else
        if ! grep -q "Interface br0" <<< "$OVS_OUTPUT_SHOW"; then
            echo -e "${RED}Bridge br0 does not have its own interface.${UNC}"
        else
            if ! grep -q "type: internal" <<< "$OVS_OUTPUT_SHOW"; then
                echo -e "${RED}Bridge br0 not integrated.${UNC}"
            else
                echo -e "${GREEN}Bridge br0 integrated.${UNC}"
                ovs_check=true
            fi
        fi
    fi
    if $ovs_check; then
        echo -e "${GREEN}Bridge and interfaces added to Open vSwitch successfully.${UNC}"
    else
        echo -e "${RED}Bridge and interfaces not added. Exiting script.${UNC}"
        exit 1
    fi
    echo -e "${GREEN}Removing IP address assigned to adapter enp0s3.${UNC}"
    ip addr flush dev enp0s3
    echo -e "${GREEN}Creating directory for management interface (MGMT).${UNC}"
    mkdir /etc/net/ifaces/MGMT
    echo -e "${GREEN}Filling settings for management interface (MGMT).${UNC}"
    cat <<EOF > /etc/net/ifaces/MGMT/options
TYPE=ovsport
BOOTPROTO=static
CONFIG_IPV4=yes
BRIDGE=br0
EOF

    echo -e "${GREEN}Assigning IP addresses and routes for directions.${UNC}"
    echo "17.0.1.2/24" > /etc/net/ifaces/MGMT/ipv4address
    echo "17.0.2.1/24" >> /etc/net/ifaces/MGMT/ipv4address    
    echo "default via 17.0.1.1" > /etc/net/ifaces/MGMT/ipv4route
    echo -e "${GREEN}Changing basic settings on adapters enp0s3, enp0s8, enp0s9.${UNC}"
    sed -i "s/BOOTPROTO=dhcp/BOOTPROTO=static/g" /etc/net/ifaces/enp0s3
    mkdir /etc/net/ifaces/enp0s{8,9}
    cp /etc/net/ifaces/enp0s3/options /etc/net/ifaces/enp0s8/
    cp /etc/net/ifaces/enp0s3/options /etc/net/ifaces/enp0s9/
    echo -e "${GREEN}Restarting network and Open vSwitch services.${UNC}"
    systemctl restart network openvswitch
    echo -e "${GREEN}Checking IP addresses and routes.${UNC}"
    ip -c --br -4 a
    ip -c --br r
    echo -e "${GREEN}Enabling 8021q kernel module and adding it permanently.${UNC}"
    modprobe 8021q && echo "8021q" | tee -a /etc/modules
    OUTPUT_CHECK_MOD=$(lsmod | grep "8021q" 2>&1)
    if grep -q "8021q" <<< "$OUTPUT_CHECK_MOD"; then
        echo -e "${GREEN}8021q kernel module enabled.${UNC}"
    else
        echo -e "${RED}8021q kernel module not enabled. Exiting script.${UNC}"
        exit 1
    fi
    echo -e "${GREEN}Installing DHCP server for assigning IP addresses to client machines.${UNC}"
    echo "nameserver 77.88.8.8" > /etc/resolv.conf
    apt-get install -y dhcp-server
    echo -e "${GREEN}Configuring DHCP server.${UNC}"
    echo -e "subnet 17.0.4.0 netmask 255.255.255.0 {\n    range 17.0.4.2 17.0.4.100;\n    option routers 17.0.4.1;\n    option domain-name-servers 77.88.8.8;\n}" > /etc/dhcp/dhcpd.conf

    name_adapter="MGMT"
    sed -i "s/DHCPDARGS=/DHCPDARGS=${name_adapter}/g" /etc/sysconfig/dhcpd
    echo -e "${GREEN}Assigning directing IP for DHCP server.${UNC}"
    echo "17.0.4.1/24" >> /etc/net/ifaces/MGMT/ipv4address
    echo -e "${GREEN}Restarting network services.${UNC}"
    systemctl restart network openvswitch
    echo -e "${GREEN}Enabling all interfaces.${UNC}"
    ip link set br0 up
    ip link set enp0s3 up
    ip link set enp0s8 up
    ip link set enp0s9 up
    ip link set MGMT up
    echo -e "${GREEN}Enabling DHCP server.${UNC}"
    systemctl enable --now dhcpd
    echo -e "${GREEN}Enabling IPv4 address forwarding.${UNC}"
    sed -i "s/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g" /etc/net/sysctl.conf
    echo "net.ipv4.conf.all.forwarding = 1" >> /etc/net/sysctl.conf
    systemctl restart network
    echo -e "${GREEN}Disabling special mode settings on Open vSwitch.${UNC}"
    ovs-vsctl set bridge br0 other_config:disable-in-band=true
    echo -e "${GREEN}Configuring Spanning Tree Protocol (STP).${UNC}"
    ovs-vsctl set bridge br0 stp_enable=true
    ovs-vsctl set bridge br0 other_config:str-priority=16384
    echo -e "${GREEN}Configuration complete.${UNC}"
    echo -e "${GREEN}Dont forget to write 'exec bash' in the terminal.${UNC}"
}

sw2_settings() {
    echo -e "${GREEN}Performing settings for SW2 machine.${UNC}"   

    hostnamectl set-hostname sw2.test-kspsuti.ru

    echo -e "${GREEN}Configuring enp0s3 adapter.${UNC}"
    sed -i "s/BOOTPROTO=dhcp/BOOTPROTO=static/g" /etc/net/ifaces/enp0s3/options
    ip addr add 17.0.2.2/24 dev enp0s3
    ip route add default via 17.0.2.1 dev enp0s3

    echo -e "${GREEN}Installing Open vSwitch.${UNC}"
    echo -e "${GREEN}Changing /etc/resolv.conf for correct domain name resolution.${UNC}"
    echo "nameserver 77.88.8.8" > /etc/resolv.conf    
    output = $(apt-get update && apt-get install -y openvswitch 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Open vSwitch installed.${UNC}"
    fi
    echo -e "${GREEN}Disabling Open vSwitch internal interfaces removal.${UNC}"
    sed -i "s/OVS_REMOVE=yes/OVS_REMOVE=no/g" /etc/net/ifaces/default/options
    echo -e "${GREEN}Enabling Open vSwitch on permanent basis.${UNC}"
    systemctl enable --now openvswitch    
    echo -e "${GREEN}Creating bridge and adding all necessary adapters inside.${UNC}"
    ovs-vsctl add-br br1
    ovs-vsctl add-port br1 enp0s3
    ovs-vsctl add-port br1 enp0s8
    ovs-vsctl add-port br1 enp0s9
    echo -e "${GREEN}Checking added bridges and adapters.${UNC}"
    OVS_OUTPUT_SHOW=$(ovs-vsctl show 2>&1)
    ovs_check=false
    if ! grep -q "Bridge br1" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Bridge br1 not created.${UNC}"
    else
        echo -e "${GREEN}Bridge br1 created.${UNC}"
    fi
    if ! grep -q "Port enp0s3" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Adapter enp0s3 not added to bridge br1.${UNC}"
    else
        echo -e "${GREEN}Adapter enp0s3 added to bridge br1.${UNC}"
    fi
    if ! grep -q "Port enp0s8" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Adapter enp0s8 not added to bridge br1.${UNC}"
    else
        echo -e "${GREEN}Adapter enp0s8 added to bridge br1.${UNC}"
    fi
    if ! grep -q "Port enp0s9" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Adapter enp0s9 not added to bridge br1.${UNC}"
    else
        echo -e "${GREEN}Adapter enp0s9 added to bridge br1.${UNC}"
    fi
    if ! grep -q "Port br1" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Bridge br1 not integrated.${UNC}"
    else
        if ! grep -q "Interface br1" <<< "$OVS_OUTPUT_SHOW"; then
            echo -e "${RED}Bridge br1 does not have its own interface.${UNC}"
        else
            if ! grep -q "type: internal" <<< "$OVS_OUTPUT_SHOW"; then
                echo -e "${RED}Bridge br1 not integrated.${UNC}"
            else
                echo -e "${GREEN}Bridge br1 integrated.${UNC}"
                ovs_check=true
            fi
        fi
    fi
    if $ovs_check; then
        echo -e "${GREEN}Bridge and interfaces added to Open vSwitch successfully.${UNC}"
    else
        echo -e "${RED}Bridge and interfaces not added. Exiting script.${UNC}"
        exit 1
    fi    
    echo -e "${GREEN}Deleting IP address assigned to enp0s3 adapter.${UNC}"
    ip addr flush dev enp0s3
    echo -e "${GREEN}Creating directory for management interface (MGMT).${UNC}"
    mkdir /etc/net/ifaces/MGMT
    echo -e "${GREEN}Filling in settings for management interface (MGMT).${UNC}"
    cat <<EOF > /etc/net/ifaces/MGMT/options
TYPE=ovsport
BOOTPROTO=static
CONFIG_IPV4=yes
BRIDGE=br1
EOF

    echo -e "${GREEN}Assigning IP addresses and routes by directions.${UNC}"
    echo "17.0.2.2/24" > /etc/net/ifaces/MGMT/ipv4address
    echo "17.0.3.1/24" >> /etc/net/ifaces/MGMT/ipv4address    
    echo "default via 17.0.2.1" > /etc/net/ifaces/MGMT/ipv4route
    echo -e "${GREEN}Changing basic settings on adapters enp0s3, enp0s8, enp0s9.${UNC}"
    sed -i "s/BOOTPROTO=dhcp/BOOTPROTO=static/g" /etc/net/ifaces/enp0s3
    mkdir /etc/net/ifaces/enp0s{8,9}
    cp /etc/net/ifaces/enp0s3/options /etc/net/ifaces/enp0s8/
    cp /etc/net/ifaces/enp0s3/options /etc/net/ifaces/enp0s9/
    echo -e "${GREEN}Restarting network and Open vSwitch services.${UNC}"
    systemctl restart network openvswitch    
    echo -e "${GREEN}Checking IP addresses and routes.${UNC}"
    ip -c --br -4 a
    ip -c --br r
    echo -e "${GREEN}Enabling 8021q kernel module and adding it permanently.${UNC}"
    modprobe 8021q && echo "8021q" | tee -a /etc/modules
    OUTPUT_CHECK_MOD=$(lsmod | grep "8021q" 2>&1)
    if grep -q "8021q" <<< "$OUTPUT_CHECK_MOD"; then
        echo -e "${GREEN}8021q kernel module enabled.${UNC}"
    else
        echo -e "${RED}8021q kernel module not enabled. Exiting script.${UNC}"
        exit 1
    fi    
    echo -e "${GREEN}Enabling IPv4 address forwarding.${UNC}"
    sed -i "s/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g" /etc/net/sysctl.conf
    echo "net.ipv4.conf.all.forwarding = 1" >> /etc/net/sysctl.conf    
    echo -e "${GREEN}Disabling special mode settings on Open vSwitch.${UNC}"
    ovs-vsctl set bridge br0 other_config:disable-in-band=true    
    echo -e "${GREEN}Enabling all interfaces.${UNC}"
    ip link set br1 up
    ip link set enp0s3 up
    ip link set enp0s8 up
    ip link set enp0s9 up
    ip link set MGMT up    
    echo -e "${GREEN}Solving ARP table problem by changing MAC address on MGMT adapter.${UNC}"
    ip link set MGMT address 00:11:22:33:44:56
    echo -e "${GREEN}Filling in MAC address on permanent basis.${UNC}"
    echo -e "address 00:11:22:33:44:56\nmtu 1500" > /etc/net/ifaces/MGMT/iplink
    echo -e "${GREEN}Configuring Spanning Tree Protocol (STP).${UNC}"
    ovs-vsctl set bridge br1 stp_enable=true
    ovs-vsctl set bridge br1 other_config:str-priority=24576
    echo -e "${GREEN}Configuration complete.${UNC}"    
    echo -e "${GREEN}Dont forget to write 'exec bash' in the terminal.${UNC}"
}

while true; do
    echo -e "${BLUE}Please select the system you want to configure${UNC}"
    echo -e "${BLUE}1) ISP;\n2) SW1;\n3) SW2;\n4) Exit;\n${UNC}"
    read -p "Select (from 1 to 4):    " choice

    case $choice in
        "1")
            isp_settings
            ;;
        "2")
            sw1_settings
            ;;
        "3")
            sw2_settings
            ;;
        "4")
            echo -e "${GREEN}Exiting the script.${UNC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid input. Please try again.${UNC}"
            ;;
    esac
done
