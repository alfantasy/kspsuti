#!/bin/bash

UNC="\033\0m"
RED="\033[31m"
BLUE="\033[34m"
GREEN="\033[32m"

echo -e "${BLUE}Специальный скрипт по настройке сетевого подключения.${UNC}"

echo "   "
echo "   "

isp_settings() {
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
}

while true; do
    echo -e "${BLUE}Выберите, пожалуйста, необходимую систему, которую собираетесь настраивать${UNC}"
    echo -e "${BLUE} 1) ISP; \n2) SW1; \n3) SW2; \n 4) Выход; \n${UNC}"
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
        *)
            echo "${RED}Некорректный ввод. Повторите попытку.${UNC}"
            ;;
    esac
done