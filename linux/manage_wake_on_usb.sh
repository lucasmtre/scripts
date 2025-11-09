#!/bin/bash

# Função para verificar o estado atual do Wake-on-USB para todos os dispositivos USB
check_wake_on_usb() {
    echo "Verificando o estado atual do Wake-on-USB para todos os dispositivos USB..."
    for usb in /sys/bus/usb/devices/*/power/wakeup; do
        echo "$usb: $(cat $usb)"
    done
}

# Função para listar dispositivos USB
list_usb_devices() {
    echo "Listando dispositivos USB..."
    lsusb
}

# Função para desabilitar Wake-on-USB para todos os dispositivos
disable_wake_on_usb_all() {
    echo "Desabilitando Wake-on-USB para todos os dispositivos USB..."
    for usb in /sys/bus/usb/devices/*/power/wakeup; do
        echo "disabled" | sudo tee $usb
    done
    update_rc_local "disable"
}

# Função para habilitar Wake-on-USB para um dispositivo específico
enable_wake_on_usb_specific() {
    list_usb_devices
    read -p "Digite o ID do dispositivo USB (por exemplo, 1-1.2): " device_id
    
    # Verificar se o dispositivo existe
    if [ ! -d /sys/bus/usb/devices/$device_id ]; then
        echo "Dispositivo USB não encontrado. Verifique o ID e tente novamente."
        exit 1
    fi
    
    echo "Habilitando Wake-on-USB para o dispositivo USB $device_id..."
    echo "enabled" | sudo tee /sys/bus/usb/devices/$device_id/power/wakeup
    update_rc_local "enable" $device_id
}

# Função para atualizar o rc.local
update_rc_local() {
    action=$1
    device_id=$2

    # Tornar o script rc.local executável se não estiver
    if [ ! -x /etc/rc.local ]; then
        sudo chmod +x /etc/rc.local
    fi

    # Remover linhas existentes relacionadas ao Wake-on-USB
    sudo sed -i '/power\/wakeup/d' /etc/rc.local

    if [ "$action" == "enable" ]; then
        # Adicionar configuração persistente para habilitar Wake-on-USB para um dispositivo específico
        if ! grep -q "echo \"enabled\" | tee /sys/bus/usb/devices/$device_id/power/wakeup" /etc/rc.local; then
            sudo sed -i "/exit 0/i echo \"enabled\" | tee /sys/bus/usb/devices/$device_id/power/wakeup" /etc/rc.local
        fi
    elif [ "$action" == "disable" ]; then
        # Adicionar configuração persistente para desabilitar Wake-on-USB para todos os dispositivos
        sudo sed -i "/exit 0/i for usb in /sys/bus/usb/devices/*/power/wakeup; do echo \"disabled\" | tee \$usb; done" /etc/rc.local
	elif [ "$action" == "remove" ]; then
        # Remover qualquer configuração de Wake-on-USB do rc.local
        sudo sed -i '/power\/wakeup/d' /etc/rc.local										  											
    fi
}

# Menu de opções
echo "Selecione uma opção:"
echo "1) Verificar o estado atual do Wake-on-USB"
echo "2) Listar dispositivos USB"
echo "3) Desabilitar Wake-on-USB para todos os dispositivos USB"
echo "4) Habilitar Wake-on-USB para um dispositivo USB específico"
echo "5) Remover habilitação global do Wake-on-USB"
echo "6) Sair"
read -p "Opção: " option

case $option in
    1)
        check_wake_on_usb
        ;;
    2)
        list_usb_devices
        ;;
    3)
        disable_wake_on_usb_all
        ;;
    4)
        enable_wake_on_usb_specific
        ;;
    5)
        update_rc_local "remove"
        echo "Habilitação global do Wake-on-USB removida."
        ;;
    6)
        echo "Saindo..."
        exit 0
        ;;
    *)
        echo "Opção inválida. Saindo..."
        exit 1
        ;;
esac
