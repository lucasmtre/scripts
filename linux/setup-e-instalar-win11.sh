#!/usr/bin/env bash
set -e

ISO_HOME_WINDOWS="/home/lucas/Downloads/Win11_25H2_BrazilianPortuguese_x64.iso"
ISO_HOME_VIRTIO="/home/lucas/Downloads/virtio-win-0.1.285.iso"

DISK_PATH="/var/lib/libvirt/images"
DISK_FILE="$DISK_PATH/win11.raw"
ISO_WINDOWS="$DISK_PATH/Win11_25H2_BrazilianPortuguese_x64.iso"
ISO_VIRTIO="$DISK_PATH/virtio-win-0.1.285.iso"

echo "=== Verificando suporte à virtualização ==="
egrep -q '(vmx|svm)' /proc/cpuinfo || { echo "ERRO: CPU sem virtualização"; exit 1; }
echo "OK ✅"

echo "=== Instalando dependências ==="
sudo apt update
sudo apt install -y qemu-system-x86 libvirt-daemon-system libvirt-clients bridge-utils virt-manager ovmf virtinst thermald pv

echo "=== Garantindo libvirtd ativo ==="
sudo systemctl enable --now libvirtd

echo "=== Garantindo grupos de permissão ==="
sudo usermod -aG kvm $USER
sudo usermod -aG libvirt $USER

echo "=== Copiando ISOs para /var/lib/libvirt/images ==="
sudo mkdir -p /var/lib/libvirt/images

echo "Caminho das ISOs:"
echo " - Windows: $ISO_HOME_WINDOWS"
echo " - VirtIO:  $ISO_HOME_VIRTIO"
echo

for SRC in "$ISO_HOME_WINDOWS" "$ISO_HOME_VIRTIO"; do
  DEST="/var/lib/libvirt/images/$(basename "$SRC")"

  if [ ! -f "$SRC" ]; then
    echo "ERRO: arquivo fonte não encontrado: $SRC"
    exit 1
  fi

  if [ -f "$DEST" ]; then
    read -rp "Arquivo '$DEST' já existe. Deseja sobrescrever? [s/N]: " resp
    resp=${resp:-N}
    if [[ "$resp" =~ ^[Ss]$ ]]; then
      echo "Apagando $DEST..."
      sudo rm -f "$DEST"
      echo "Copiando $SRC -> $DEST..."
      sudo pv "$SRC" | sudo dd of="$DEST" bs=4M status=progress
    else
      echo "Pulando cópia de $(basename "$DEST")."
    fi
  else
    echo "Copiando $SRC -> $DEST..."
    sudo pv "$SRC" | sudo dd of="$DEST" bs=4M status=progress
  fi
done

echo "OK ✅"

echo "=== Configurando HugePages (se já não configurado) ==="
grep -q "vm.nr_hugepages=1024" /etc/sysctl.conf || echo "vm.nr_hugepages=1024" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "=== Ajustando política de swap ==="
grep -q "vm.swappiness=10" /etc/sysctl.conf || echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
sudo sysctl vm.swappiness=10

echo "=== Ativando thermald ==="
sudo systemctl enable --now thermald

echo "=== Configurar swap ==="
read -rp "Deseja configurar ou alterar o disco de swap? [S/n]: " change_swap
change_swap=${change_swap:-S}

if [[ "$change_swap" =~ ^[Ss]$ ]]; then
  echo
  echo "Discos físicos disponíveis:"
  lsblk -dn -o NAME,SIZE,TYPE | awk '$3=="disk"{printf "%s - %s\n",$1,$2}'
  echo

  mapfile -t disks < <(lsblk -dn -o NAME,SIZE,TYPE | awk '$3=="disk"{print "/dev/"$1":"$2}')
  PS3="Escolha o disco (ou 0 para cancelar): "

  select entry in "${disks[@]}"; do
    [[ -z "$entry" ]] && echo "Cancelado." && break
    SWAP_DISK="${entry%%:*}"
    read -rp "⚠️ Isso APAGARÁ TUDO em $SWAP_DISK. Confirmar? [s/N]: " confirm
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
      echo "=== Aplicando nova swap ==="
      sudo swapoff -a
      sudo sed -i '/swap/d' /etc/fstab
      sudo mkswap -f "$SWAP_DISK"
      sudo swapon "$SWAP_DISK"
      echo "$SWAP_DISK none swap sw,pri=100 0 0" | sudo tee -a /etc/fstab >/dev/null
      break
    else
      echo "Cancelado. Escolha outro ou 0 para sair."
    fi
  done
else
  echo "Mantendo swap atual."
fi

echo "=== Garantindo rede 'default' do libvirt (system) ==="

if sudo virsh --connect qemu:///system net-list --all | grep -q default; then
  echo "Rede 'default' já existe."
else
  echo "Rede 'default' não encontrada. Criando..."
  sudo virsh --connect qemu:///system net-define /usr/share/libvirt/networks/default.xml
fi

if sudo virsh --connect qemu:///system net-list --all | grep default | grep -q inactive; then
  echo "Rede 'default' está inativa. Iniciando..."
  sudo virsh --connect qemu:///system net-start default
fi

sudo virsh --connect qemu:///system net-autostart default >/dev/null 2>&1 || true

echo "Estado final da rede (system):"
sudo virsh --connect qemu:///system net-list --all


echo "=== Criando diretório da VM ==="
mkdir -p "$DISK_PATH"

echo "=== Criando disco RAW de 60GB (se não existe) ==="
echo "Removendo disco antigo (se existir)..."
sudo rm -f "$DISK_FILE"
echo "Criando disco em $DISK_FILE..."   
[ ! -f "$DISK_FILE" ] && sudo qemu-img create -f raw "$DISK_FILE" 60G

echo "=== Criando VM Windows 11 ==="
echo "Removendo VM antiga (se existir)..."
sudo virsh --connect qemu:///system destroy Windows11 2>/dev/null || true
echo "Removendo definição antiga (se existir)..."
sudo virsh --connect qemu:///system undefine Windows11 --remove-all-storage 2>/dev/null || true
echo "Removendo NVRAM antiga (se existir)..."
sudo virsh --connect qemu:///system undefine Windows11 --nvram 2>/dev/null || true
echo "Criando nova VM..."
if ! sudo virsh --connect qemu:///system list --all | grep -q Windows11; then
    # Criar diretório para NVRAM se ainda não existir
    sudo rm -f /var/lib/libvirt/qemu/nvram/Windows11_VARS.fd
    sudo mkdir -p /var/lib/libvirt/qemu/nvram/

    # Criar arquivo VARS exclusivo para esta VM
    sudo cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd /var/lib/libvirt/qemu/nvram/Windows11_VARS.fd
    sudo chown libvirt-qemu:libvirt-qemu /var/lib/libvirt/qemu/nvram/Windows11_VARS.fd

    sudo virt-install --connect qemu:///system \
    --name Windows11 \
    --os-variant win11 \
    --memory 8192 \
    --vcpus 3,maxvcpus=8 \
    --cpu host-passthrough \
    --boot loader=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd,loader.type=pflash,loader.readonly=yes,nvram=/var/lib/libvirt/qemu/nvram/Windows11_VARS.fd \
    --tpm model=tpm-tis \
    --cdrom "$ISO_WINDOWS" \
    --disk path="$DISK_FILE",format=raw,bus=virtio,cache=writeback \
    --disk path="$ISO_WINDOWS",device=cdrom,bus=sata \
    --disk path="$ISO_VIRTIO",device=cdrom,bus=sata \
    --network network=default,model=virtio \
    --graphics spice \
    --video virtio \
    --noautoconsole
    echo "✅ VM criada com sucesso!"
else
  echo "VM já existe — pulando criação."
fi

echo
echo "✅ Ambiente finalizado!"
echo "⚠️ Agora REINICIE o computador: sudo reboot"
echo
echo "Depois abra o Virt-Manager:"
echo "  virt-manager"
echo
echo "Inicie a VM → instale Windows 11 normalmente."
echo "Quando não aparecer o disco, clique: Load Driver → viostor + NetKVM"
echo
echo "Quando terminar a instalação, volte aqui e digite:  instalado"
