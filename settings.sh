#!/bin/bash

UNC="\033\0m"
RED="\033[31m"
BLUE="\033[34m"
GREEN="\033[32m"

echo -e "${BLUE}Специальный скрипт по настройке сетевого подключения.${UNC}"

echo "   "

isp_settings() {
    echo -e "${GREEN}Выполнение настроек для машины ISP.${UNC}"

    echo -e "${GREEN}Назначаем название машины.${UNC}"
    hostnamectl set-hostname ISP; exec bash

    echo -e "${GREEN}Создаем директорию для адаптера в сторону SW1.${UNC}"
    mkdir /etc/net/ifaces/enp0s8

    echo -e "${GREEN}Заполняем файл конфигурации адаптера в сторону SW1.${UNC}"
    cat <<EOF > /etc/net/ifaces/enp0s8/options
TYPE=eth
BOOTPROTO=static
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
EOF

    echo -e "${GREEN}Назначаем IP-адрес на данный интерфейс${UNC}"
    echo "17.0.1.1/24" > /etc/net/ifaces/enp0s8/ipv4address
    echo -e "${GREEN}Включаем переадресацию адресов IPv4${UNC}"
    sed -i "s/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g" /etc/net/sysctl.conf
    echo "net.ipv4.conf.all.forwarding = 1" >> /etc/net/sysctl.conf
    systemctl restart network
    echo -e "${GREEN}Выводим IP-адреса для проверки${UNC}"
    ip -c --br -4 a

    echo -e "${GREEN}Устанавливаем nftables для настройки NAT (доступ в сеть с других машин).${UNC}"
    echo -e "${GREEN}Изменение /etc/resolv.conf для правильного обращения к доменным именам.${UNC}"
    echo "nameserver 77.88.8.8" > /etc/resolv.conf
    output=$(apt-get update && apt-get install -y nftables 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}nftables установлен.${UNC}"
    fi
    echo -e "${GREEN}Активируем сервис nftables.${UNC}"
    systemctl enable --now nftables
    echo -e "${GREEN}Интеграция всех необходимых правил nftables и автоматическое их сохранение.${UNC}"
    nft add table ip nat
    nft add chain ip nat postrouting '{ type nat hook postrouting priority 0; }'
    nft add rule ip nat postrouting ip saddr 17.0.1.0/24 oifname "enp0s3" counter masquerade
    nft add rule ip nat postrouting ip saddr 17.0.2.0/24 oifname "enp0s3" counter masquerade
    nft add rule ip nat postrouting ip saddr 17.0.3.0/24 oifname "enp0s3" counter masquerade
    nft add rule ip nat postrouting ip saddr 17.0.4.0/24 oifname "enp0s3" counter masquerade
    echo -e "${GREEN}Сохраняем правила в /etc/nftables/nftables.nft.${UNC}"
    nft list ruleset | tail -n9 | tee -a /etc/nftables/nftables.nft
    echo -e "${GREEN}Перезагружаем сервис nftables.${UNC}"
    systemctl restart nftables
    echo -e "${GREEN}Добавляем все необходимые прослушиваемые в будущем маршруты.${UNC}"
    echo "17.0.2.0/24 via 17.0.1.2" >> /etc/net/ifaces/enp0s8/ipv4route
    echo "17.0.3.0/24 via 17.0.1.2" >> /etc/net/ifaces/enp0s8/ipv4route
    echo "17.0.4.0/24 via 17.0.1.2" >> /etc/net/ifaces/enp0s8/ipv4route
    echo -e "${GREEN}Настройка закончена.${UNC}"
}

sw1_settings() {
    echo -e "${GREEN}Выполнение настройки для машины SW1.${UNC}"

    echo -e "${GREEN}Назначаем название машины.${UNC}"
    hostnamectl set-hostname sw1.test-kspsuti.ru; exec bash

    echo -e "${GREEN}Временное назначение IP-адреса на направляющий адаптер enp0s3 в сторону ISP.${UNC}"
    ip addr add 17.0.1.2/24 dev enp0s3
    ip route add default via 17.0.1.1 dev enp0s3
    ip link set enp0s3 up

    echo -e "${GREEN}Установка Open vSwitch.${UNC}"
    echo -e "${GREEN}Изменение /etc/resolv.conf для правильного обращения к доменным именам.${UNC}"
    echo "nameserver 77.88.8.8" > /etc/resolv.conf
    output = $(apt-get update && apt-get install -y openvswitch 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Open vSwitch установлен.${UNC}"
    fi
    echo -e "${GREEN}Отключение удаления специальных внутренних адаптеров, создаваемых Open vSwitch.${UNC}"
    sed -i "s/OVS_REMOVE=yes/OVS_REMOVE=no/g" /etc/net/ifaces/default/options
    echo -e "${GREEN}Включаем Open vSwitch на постоянной основе.${UNC}"
    systemctl enable --now openvswitch
    echo -e "${GREEN}Создание моста и добавление всех необходимых адаптеров внутрь него.${UNC}"
    ovs-vsctl add-br br0
    ovs-vsctl add-port br0 enp0s3
    ovs-vsctl add-port br0 enp0s8
    ovs-vsctl add-port br0 enp0s9
    echo -e "${GREEN}Проверка добавленных мостов и адаптеров.${UNC}"
    OVS_OUTPUT_SHOW=$(ovs-vsctl show 2>&1)
    ovs_check=false
    if ! grep -q "Bridge br0" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Мост br0 не создан.${UNC}"
    else
        echo -e "${GREEN}Мост br0 создан.${UNC}"
    fi
    if ! grep -q "Port enp0s3" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Адаптер enp0s3 не добавлен в мост br0.${UNC}"
    else
        echo -e "${GREEN}Адаптер enp0s3 добавлен в мост br0.${UNC}"
    fi
    if ! grep -q "Port enp0s8" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Адаптер enp0s8 не добавлен в мост br0.${UNC}"
    else
        echo -e "${GREEN}Адаптер enp0s8 добавлен в мост br0.${UNC}"
    fi
    if ! grep -q "Port enp0s9" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Адаптер enp0s9 не добавлен в мост br0.${UNC}"
    else
        echo -e "${GREEN}Адаптер enp0s9 добавлен в мост br0.${UNC}"
    fi
    if ! grep -q "Port br0" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Мост br0 не интегрирован.${UNC}"
    else
        if ! grep -q "Interface br0" <<< "$OVS_OUTPUT_SHOW"; then
            echo -e "${RED}Мост br0 не имеет собственного интерфейса.${UNC}"
        else
            if ! grep -q "type: internal" <<< "$OVS_OUTPUT_SHOW"; then
                echo -e "${RED}Мост br0 не интегрирован.${UNC}"
            else
                echo -e "${GREEN}Мост br0 интегрирован.${UNC}"
                ovs_check=true
            fi
        fi
    fi
    if $ovs_check; then
        echo -e "${GREEN}Мост и интерфейсы добавлены в Open vSwitch успешно.${UNC}"
    else
        echo -e "${RED}Мост и интерфейсы не добавлены. Завершение скрипта.${UNC}"
        exit 1
    fi
    echo -e "${GREEN}Удаляем IP-адрес, назначенный на адаптер enp0s3.${UNC}"
    ip addr flush dev enp0s3
    echo -e "${GREEN}Создаем директорию для интерфейса управления (MGMT).${UNC}"
    mkdir /etc/net/ifaces/MGMT
    echo -e "${GREEN}Заполняем настройки для интерфейса управления (MGMT).${UNC}"
    cat <<EOF > /etc/net/ifaces/MGMT/options
TYPE=ovsport
BOOTPROTO=static
CONFIG_IPV4=yes
BRIDGE=br0
EOF
    echo -e "${GREEN}Назначение IP-адресов и маршрутов по направлениям.${UNC}"
    echo "17.0.1.2/24" > /etc/net/ifaces/MGMT/ipv4address
    echo "17.0.2.1/24" >> /etc/net/ifaces/MGMT/ipv4address    
    echo "default via 17.0.1.1" > /etc/net/ifaces/MGMT/ipv4route
    echo -e "${GREEN}Изменение базовых настроек на адаптерах enp0s3, enp0s8, enp0s9.${UNC}"
    sed -i "s/BOOTPROTO=dhcp/BOOTPROTO=static/g" /etc/net/ifaces/enp0s3
    mkdir /etc/net/ifaces/enp0s{8,9}
    cp /etc/net/ifaces/enp0s3/options /etc/net/ifaces/enp0s8/
    cp /etc/net/ifaces/enp0s3/options /etc/net/ifaces/enp0s9/
    echo -e "${GREEN}Перезагрузка сервисов сети и Open vSwitch.${UNC}"
    systemctl restart network openvswitch
    echo -e "${GREEN}Проверка IP адресов и маршрутов.${UNC}"
    ip -c --br -4 a
    ip -c --br r
    echo -e "${GREEN}Включение модуля ядра 8021q и добавление его на постоянной основе.${UNC}"
    modprobe 8021q $$ echo "8021q" | tee -a /etc/modules
    OUTPUT_CHECK_MOD=$(lsmod | grep "8021q" 2>&1)
    if grep -q "8021q" <<< "$OUTPUT_CHECK_MOD"; then
        echo -e "${GREEN}Модуль ядра 8021q включен.${UNC}"
    else
        echo -e "${RED}Модуль ядра 8021q не включен. Завершение скрипта.${UNC}"
        exit 1
    fi
    echo -e "${GREEN}Установка DHCP-сервера для раздачи IP-адресов на клиентские машины.${UNC}"
    echo "nameserver 77.88.8.8" > /etc/resolv.conf
    apt-get install -y dhcp-server
    echo -e "${GREEN}Настройка DHCP-сервера.${UNC}"
    cat <<EOF > /etc/dhcp/dhcpd.conf
subnet 17.0.4.0 netmask 255.255.255.0 {
    range 17.0.4.2 17.0.4.100;
    option routers 17.0.4.1;
    option domain-name-servers 77.88.8.8;
}
EOF
    name_adapter="MGMT"
    sed -i "s/DHCPDARGS=/DHCPDARGS=${name_adapter}/g" /etc/sysconfig/dhcpd
    echo -e "${GREEN}Задаем направляющий IP для DHCP-сервера.${UNC}"
    echo "17.0.4.1/24" >> /etc/net/ifaces/MGMT/ipv4address
    echo -e "${GREEN}Перезагрузка сервисов сетию${UNC}"
    systemctl restart network openvswitch
    echo -e "${GREEN}Включаем все интерфейсы.${UNC}"
    ip link set br0 up
    ip link set enp0s3 up
    ip link set enp0s8 up
    ip link set enp0s9 up
    ip link set MGMT up
    echo -e "${GREEN}Включаем DHCP-сервер.${UNC}"
    systemctl enable --now dhcpd
    echo -e "${GREEN}Включаем переадресацию адресов IPv4${UNC}"
    sed -i "s/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g" /etc/net/sysctl.conf
    echo "net.ipv4.conf.all.forwarding = 1" >> /etc/net/sysctl.conf
    systemctl restart network
    echo -e "${GREEN}Отключаем настройку специального режима на Open vSwitch.${UNC}"
    ovs-vsctl set bridge br0 other_config:disable-in-band=true
    echo -e "${GREEN}Настройка протокола основного дерева STP.${UNC}"
    ovs-vsctl set bridge br0 stp_enable=true
    ovs-vsctl set bridge br0 other_config:str-priority=16384
    echo -e "${GREEN}Настройка закончена.${UNC}"
}

sw2_settings() {
    echo -e "${GREEN}Выполнение настройки для машины SW2.${UNC}"   

    hostnamectl set-hostname sw2.test-kspsuti.ru; exec bash

    echo -e "${GREEN}Настройка направляющего адаптера enp0s3.${UNC}"
    sed -i "s/BOOTPROTO=dhcp/BOOTPROTO=static/g" /etc/net/ifaces/enp0s3/options
    ip addr add 17.0.2.2/24 dev enp0s3
    ip route add default via 17.0.2.1 dev enp0s3

    echo -e "${GREEN}Установка Open vSwitch.${UNC}"
    echo -e "${GREEN}Изменение /etc/resolv.conf для правильного обращения к доменным именам.${UNC}"
    echo "nameserver 77.88.8.8" > /etc/resolv.conf    
    output = $(apt-get update && apt-get install -y openvswitch 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Open vSwitch установлен.${UNC}"
    fi
    echo -e "${GREEN}Отключение удаления специальных внутренних адаптеров, создаваемых Open vSwitch.${UNC}"
    sed -i "s/OVS_REMOVE=yes/OVS_REMOVE=no/g" /etc/net/ifaces/default/options
    echo -e "${GREEN}Включаем Open vSwitch на постоянной основе.${UNC}"
    systemctl enable --now openvswitch    
    echo -e "${GREEN}Создание моста и добавление всех необходимых адаптеров внутрь него.${UNC}"
    ovs-vsctl add-br br1
    ovs-vsctl add-port br1 enp0s3
    ovs-vsctl add-port br1 enp0s8
    ovs-vsctl add-port br1 enp0s9
    echo -e "${GREEN}Проверка добавленных мостов и адаптеров.${UNC}"
    OVS_OUTPUT_SHOW=$(ovs-vsctl show 2>&1)
    ovs_check=false
    if ! grep -q "Bridge br1" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Мост br1 не создан.${UNC}"
    else
        echo -e "${GREEN}Мост br1 создан.${UNC}"
    fi
    if ! grep -q "Port enp0s3" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Адаптер enp0s3 не добавлен в мост br1.${UNC}"
    else
        echo -e "${GREEN}Адаптер enp0s3 добавлен в мост br1.${UNC}"
    fi
    if ! grep -q "Port enp0s8" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Адаптер enp0s8 не добавлен в мост br1.${UNC}"
    else
        echo -e "${GREEN}Адаптер enp0s8 добавлен в мост br1.${UNC}"
    fi
    if ! grep -q "Port enp0s9" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Адаптер enp0s9 не добавлен в мост br1.${UNC}"
    else
        echo -e "${GREEN}Адаптер enp0s9 добавлен в мост br1.${UNC}"
    fi
    if ! grep -q "Port br1" <<< "$OVS_OUTPUT_SHOW"; then
        echo -e "${RED}Мост br1 не интегрирован.${UNC}"
    else
        if ! grep -q "Interface br1" <<< "$OVS_OUTPUT_SHOW"; then
            echo -e "${RED}Мост br1 не имеет собственного интерфейса.${UNC}"
        else
            if ! grep -q "type: internal" <<< "$OVS_OUTPUT_SHOW"; then
                echo -e "${RED}Мост br1 не интегрирован.${UNC}"
            else
                echo -e "${GREEN}Мост br1 интегрирован.${UNC}"
                ovs_check=true
            fi
        fi
    fi
    if $ovs_check; then
        echo -e "${GREEN}Мост и интерфейсы добавлены в Open vSwitch успешно.${UNC}"
    else
        echo -e "${RED}Мост и интерфейсы не добавлены. Завершение скрипта.${UNC}"
        exit 1
    fi    
    echo -e "${GREEN}Удаляем IP-адрес, назначенный на адаптер enp0s3.${UNC}"
    ip addr flush dev enp0s3
    echo -e "${GREEN}Создаем директорию для интерфейса управления (MGMT).${UNC}"
    mkdir /etc/net/ifaces/MGMT
    echo -e "${GREEN}Заполняем настройки для интерфейса управления (MGMT).${UNC}"
    cat <<EOF > /etc/net/ifaces/MGMT/options
TYPE=ovsport
BOOTPROTO=static
CONFIG_IPV4=yes
BRIDGE=br1
EOF    
    echo -e "${GREEN}Назначение IP-адресов и маршрутов по направлениям.${UNC}"
    echo "17.0.2.2/24" > /etc/net/ifaces/MGMT/ipv4address
    echo "17.0.3.1/24" >> /etc/net/ifaces/MGMT/ipv4address    
    echo "default via 17.0.2.1" > /etc/net/ifaces/MGMT/ipv4route
    echo -e "${GREEN}Изменение базовых настроек на адаптерах enp0s3, enp0s8, enp0s9.${UNC}"
    sed -i "s/BOOTPROTO=dhcp/BOOTPROTO=static/g" /etc/net/ifaces/enp0s3
    mkdir /etc/net/ifaces/enp0s{8,9}
    cp /etc/net/ifaces/enp0s3/options /etc/net/ifaces/enp0s8/
    cp /etc/net/ifaces/enp0s3/options /etc/net/ifaces/enp0s9/
    echo -e "${GREEN}Перезагрузка сервисов сети и Open vSwitch.${UNC}"
    systemctl restart network openvswitch    
    echo -e "${GREEN}Проверка IP адресов и маршрутов.${UNC}"
    ip -c --br -4 a
    ip -c --br r
    echo -e "${GREEN}Включение модуля ядра 8021q и добавление его на постоянной основе.${UNC}"
    modprobe 8021q $$ echo "8021q" | tee -a /etc/modules
    OUTPUT_CHECK_MOD=$(lsmod | grep "8021q" 2>&1)
    if grep -q "8021q" <<< "$OUTPUT_CHECK_MOD"; then
        echo -e "${GREEN}Модуль ядра 8021q включен.${UNC}"
    else
        echo -e "${RED}Модуль ядра 8021q не включен. Завершение скрипта.${UNC}"
        exit 1
    fi    
    echo -e "${GREEN}Включаем переадресацию адресов IPv4${UNC}"
    sed -i "s/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g" /etc/net/sysctl.conf
    echo "net.ipv4.conf.all.forwarding = 1" >> /etc/net/sysctl.conf    
    echo -e "${GREEN}Отключаем настройку специального режима на Open vSwitch.${UNC}"
    ovs-vsctl set bridge br0 other_config:disable-in-band=true    
    echo -e "${GREEN}Включаем все интерфейсы.${UNC}"
    ip link set br1 up
    ip link set enp0s3 up
    ip link set enp0s8 up
    ip link set enp0s9 up
    ip link set MGMT up    
    echo -e "${GREEN}Решение проблемы ARP-таблицы при помощи изменения MAC-адреса на MGMT адаптере.${UNC}"
    ip link set MGMT address 00:11:22:33:44:56
    echo -e "${GREEN}Заполнение MAC-адреса на постоянной основе.${UNC}"
    echo -e "address 00:11:22:33:44:56\nmtu 1500" > /etc/net/ifaces/MGMT/iplink
    echo -e "${GREEN}Настройка протокола основного дерева STP.${UNC}"
    ovs-vsctl set bridge br1 stp_enable=true
    ovs-vsctl set bridge br1 other_config:str-priority=24576
    echo -e "${GREEN}Настройка закончена.${UNC}"    
}

while true; do
    echo -e "${BLUE}Выберите, пожалуйста, необходимую систему, которую собираетесь настраивать${UNC}"
    echo -e "${BLUE}1) ISP;\n2) SW1;\n3) SW2;\n4) Выход;\n${UNC}"
    read -p "Выберите (от 1 до 4):    " choice

    case $choice in
        "1")
            isp_settings
            ;;
        "2")
            ;;
        "3")
            ;;
        "4")
            echo -e "${GREEN}Выход из скрипта.${UNC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Некорректный ввод. Повторите попытку.${UNC}"
            ;;
    esac
done