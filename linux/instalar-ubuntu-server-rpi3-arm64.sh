#!/bin/bash

set -e

# CONFIGURAÇÕES
WORK_DIR="$HOME/Downloads/ubuntu-rpi3"
IMG_URL="https://cdimage.ubuntu.com/releases/22.04/release/ubuntu-22.04.5-preinstalled-server-arm64+raspi.img.xz"
IMG_NAME="$(basename "$IMG_URL")"
IMG_PATH="$WORK_DIR/$IMG_NAME"
IMG_FILE="${IMG_PATH%.xz}"
USER_NAME="piadmin"
USER_PASSWORD="pi123"  # sinta-se à vontade para alterar

echo "=== Instalação do Ubuntu 22.04.5 no Raspberry Pi 3 ==="
echo "Diretório de trabalho: $WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "✅ Baixando a imagem..."
wget -c "$IMG_URL" -O "$IMG_PATH"

echo "📦 Descompactando a imagem..."
xz -d -v "$IMG_PATH"

echo ""
echo "🔍 Dispositivos disponíveis:"
lsblk
echo ""
read -rp "→ Digite o dispositivo SD (ex: /dev/mmcblk0 ou /dev/sdb): " SD_DEVICE

if [[ ! "$SD_DEVICE" =~ ^/dev/(sd[a-z]|mmcblk[0-9])$ ]]; then
  echo "⚠️  Dispositivo inválido."
  exit 1
fi

read -rp "⚠️  Gravar em $SD_DEVICE? Isso apagará tudo! (s/n): " CONF
if [[ "$CONF" != "s" ]]; then
  echo "❌ Cancelado."
  exit 0
fi

echo "💾 Gravando imagem no cartão..."
sudo dd if="$IMG_FILE" of="$SD_DEVICE" bs=4M status=progress conv=fsync
sync
sleep 5

BOOT_PART=$(lsblk -ln -o NAME "${SD_DEVICE}" | grep -E 'p1$|1$' | head -n1)
BOOT_DEV="/dev/$BOOT_PART"
BOOT_MOUNT="$WORK_DIR/bootfs"

echo ""
echo "📌 Montando partição de boot ($BOOT_DEV)..."
mkdir -p "$BOOT_MOUNT"
sudo mount "$BOOT_DEV" "$BOOT_MOUNT"

echo "👤 Criando usuário '$USER_NAME' com acesso root via cloud-init..."
cat <<EOF | sudo tee "$BOOT_MOUNT/user-data" >/dev/null
#cloud-config
users:
  - name: $USER_NAME
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: $(echo "$USER_PASSWORD" | openssl passwd -6 -stdin)
chpasswd:
  expire: false
ssh_pwauth: true
disable_root: false
EOF

sudo touch "$BOOT_MOUNT/ssh"

echo "🧹 Desmontando partição de boot..."
sudo umount "$BOOT_MOUNT"

echo ""
echo "✅ Concluído! Usuário: $USER_NAME / Senha: $USER_PASSWORD"
echo "Coloque o cartão no Raspberry Pi 3 e faça login."
