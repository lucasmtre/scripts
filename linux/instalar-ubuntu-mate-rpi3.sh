#!/bin/bash

set -e

# CONFIGURAÇÕES
WORK_DIR="$HOME/Downloads/ubuntu-mate-rpi3"
IMG_URL="https://releases.ubuntu-mate.org/jammy/arm64/ubuntu-mate-22.04.4-desktop-arm64+raspi.img.xz"
IMG_NAME="$(basename "$IMG_URL")"
IMG_PATH="$WORK_DIR/$IMG_NAME"
IMG_FILE="${IMG_PATH%.xz}"

echo "=== Instalação do Ubuntu MATE 22.04 para Raspberry Pi 3 ==="
echo "Usando diretório: $WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "📥 Baixando imagem oficial Ubuntu MATE..."
wget -c "$IMG_URL" -O "$IMG_PATH"

echo "📦 Descompactando imagem..."
xz -d -v "$IMG_PATH"

echo ""
echo "📍 Dispositivos disponíveis:"
lsblk
echo ""
read -rp "→ Digite o caminho do cartão SD (ex: /dev/mmcblk0 ou /dev/sdb): " SD_DEVICE

if [[ ! "$SD_DEVICE" =~ ^/dev/(sd[a-z]|mmcblk[0-9])$ ]]; then
    echo "❌ Dispositivo inválido. Abortando."
    exit 1
fi

read -rp "⚠️  Isso apagará todos os dados em $SD_DEVICE. Continuar? (s/n): " CONF
if [[ "$CONF" != "s" ]]; then
    echo "❌ Operação cancelada."
    exit 0
fi

echo "💾 Gravando imagem no cartão SD..."
sudo dd if="$IMG_FILE" of="$SD_DEVICE" bs=4M status=progress conv=fsync
sync

echo ""
echo "✅ Cartão SD pronto com Ubuntu MATE 22.04."
echo "Insira no Raspberry Pi 3 e inicie com interface gráfica."
