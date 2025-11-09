#!/usr/bin/env bash
set -e

echo "=== Instalando dependências necessárias ==="
sudo apt update
sudo apt install -y virtinst virt-manager qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils

# Caminhos das ISOs (ajustados conforme você informou)
ISO_WINDOWS="/home/lucas/Downloads/Win11_25H2_BrazilianPortuguese_x64.iso"
ISO_VIRTIO="/home/lucas/Downloads/virtio-win-0.1.285.iso"

# Caminho onde o disco da VM será criado
DISK_PATH="$HOME/VirtualMachines"
DISK_FILE="$DISK_PATH/win11.raw"

echo "=== Criando diretório da VM (se não existir) ==="
mkdir -p "$DISK_PATH"

echo "=== Criando disco RAW de 60GB ==="
qemu-img create -f raw "$DISK_FILE" 60G

echo "=== Criando VM no libvirt ==="
virt-install \
  --name Windows11 \
  --os-variant win11 \
  --memory 8192 \
  --vcpus 3,maxvcpus=8 \
  --cpu host-passthrough \
  --hvm \
  --boot loader=/usr/share/OVMF/OVMF_CODE.fd,loader.readonly=yes,loader.type=pflash \
  --tpm model=tpm-tis \
  --disk path="$DISK_FILE",format=raw,bus=virtio,cache=writeback \
  --cdrom "$ISO_WINDOWS" \
  --disk path="$ISO_VIRTIO",device=cdrom,bus=sata \
  --network network=default,model=virtio \
  --graphics spice \
  --video virtio \
  --sound none \
  --noautoconsole

echo
echo "✅ VM criada com sucesso!"
echo
echo "Abra o Virt-Manager:"
echo "  virt-manager"
echo
echo "Inicie a VM 'Windows11' e faça a instalação normalmente."
echo
echo "Quando o instalador pedir o disco e não aparecer, clique:"
echo "  → Load Driver"
echo "  → Selecione a ISO VirtIO"
echo "  → Drivers: viostor (disco) e NetKVM (rede)"
echo
echo "Depois me avise para aplicar as otimizações finais (Hyper-V, HugePages, prioridades)."
