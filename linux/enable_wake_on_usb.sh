#!/bin/bash

# Verificar o estado atual do Wake-on-USB para todos os dispositivos USB
echo "Verificando o estado atual do Wake-on-USB para todos os dispositivos USB..."
for usb in /sys/bus/usb/devices/*/power/wakeup; do
    echo "$usb: $(cat $usb)"
done

# Listar dispositivos USB conectados
echo "Listando dispositivos USB..."
lsusb

# Solicitar o ID do dispositivo USB do receptor do mouse sem fio ao usuário
read -p "Digite o ID do dispositivo USB (por exemplo, 1-1.2): " device_id

# Verificar se o dispositivo existe
if [ ! -d /sys/bus/usb/devices/$device_id ]; then
    echo "Dispositivo USB não encontrado. Verifique o ID e tente novamente."
    exit 1
fi

# Habilitar Wake-on-USB para o receptor do mouse
echo "Habilitando Wake-on-USB para o dispositivo USB $device_id..."
echo "enabled" | sudo tee /sys/bus/usb/devices/$device_id/power/wakeup

# Adicionar regra udev para habilitar Wake-on-USB
echo 'ACTION=="add", SUBSYSTEM=="usb", TEST=="power/wakeup", ATTR{power/wakeup}="enabled"' | sudo tee /etc/udev/rules.d/90-usb-wakeup.rules

# Tornar o script rc.local executável se não estiver
if [ ! -x /etc/rc.local ]; then
    sudo chmod +x /etc/rc.local
fi

# Adicionar configuração persistente ao rc.local
if ! grep -q 'echo "enabled" | tee /sys/bus/usb/devices/*/power/wakeup' /etc/rc.local; then
    sudo sed -i '/exit 0/i echo "enabled" | tee /sys/bus/usb/devices/*/power/wakeup' /etc/rc.local
fi

echo "Configurações de Wake-on-USB aplicadas com sucesso."
