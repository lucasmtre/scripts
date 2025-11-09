#!/bin/bash
set -e

WORK_DIR="$HOME/Downloads/ubuntu-mate-rpi3-64"
IMG_URL="https://releases.ubuntu-mate.org/22.04/arm64/ubuntu-mate-22.04-desktop-arm64+raspi.img.xz"
IMG_NAME="$(basename "$IMG_URL")"
IMG_PATH="$WORK_DIR/$IMG_NAME"
IMG_FILE="${IMG_PATH%.xz}"

rm -rf $WORK_DIR

echo "=== Ubuntu MATE 22.04 (64-bit) para Raspberry Pi 3 ==="
echo "📁 Diretório de trabalho: $WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Baixar se necessário
if [[ -f "$IMG_PATH" ]]; then
    echo "✔️ Imagem já baixada: $IMG_NAME"
else
    echo "📥 Baixando imagem..."
    wget -c "$IMG_URL" -O "$IMG_PATH"
fi

# Descompactar se necessário
echo "📦 Deletando imagem antiga imagem..."
rm -rf $IMG_FILE
echo "📦 Descompactando imagem..."
xz -d -v "$IMG_PATH"

echo ""
lsblk
echo ""
read -rp "→ Indique o dispositivo SD (ex: /dev/mmcblk0 ou /dev/sdb): " SD

if [[ ! "$SD" =~ ^/dev/(sd[a-z]|mmcblk[0-9])$ ]]; then
    echo "❌ Dispositivo inválido"; exit 1
fi

# Pergunta se deve sobrescrever o cartão
read -rp "⚠️ Deseja sobrescrever (gravar novamente) a imagem no cartão SD $SD? (s/n): " OVERWRITE
if [[ "$OVERWRITE" == "s" ]]; then
    read -rp "⚠️ Isso apagará TODOS os dados em $SD. Confirmar? (s/n): " CONFIRM
    if [[ "$CONFIRM" != "s" ]]; then
        echo "⛔ Operação cancelada."
        exit 0
    fi
    echo "💾 Gravando imagem..."
    sudo dd if="$IMG_FILE" of="$SD" bs=4M status=progress conv=fsync
    sync && sleep 5
else
    echo "ℹ️ Pulando gravação da imagem. Prosseguindo com ajustes no config.txt..."
fi

# Detecta partição boot
BOOT_PART=$(lsblk -ln -o NAME "$SD" | grep -E 'p1$|1$' | head -n1)
BOOT_DEV="/dev/$BOOT_PART"

# Detecta se já está montado
MOUNTED_BOOT=$(lsblk -no MOUNTPOINT "$BOOT_DEV")
if [[ -n "$MOUNTED_BOOT" ]]; then
    echo "🔄 A partição já está montada em: $MOUNTED_BOOT"
    BOOT_MOUNT="$MOUNTED_BOOT"
else
    BOOT_MOUNT="$WORK_DIR/bootfs"
    mkdir -p "$BOOT_MOUNT"
    echo "🔧 Montando /boot ($BOOT_DEV) manualmente em $BOOT_MOUNT..."
    sudo mount "$BOOT_DEV" "$BOOT_MOUNT"
fi

echo "✏️ Corrigindo config.txt (vc4-kms → vc4-fkms)..."
sudo sed -i 's/^dtoverlay=vc4-kms-v3d/dtoverlay=vc4-fkms-v3d/' "$BOOT_MOUNT/config.txt"

# Desmonta se foi montado manualmente
if [[ "$BOOT_MOUNT" == "$WORK_DIR/bootfs" ]]; then
    echo "🧹 Desmontando /boot..."
    sudo fuser -kv "$BOOT_MOUNT" 2>/dev/null || true
    sleep 1
    sudo umount "$BOOT_MOUNT" || sudo umount -l "$BOOT_MOUNT"
else
    echo "ℹ️ Montagem automática detectada. Não desmontado."
fi

echo ""
echo "✅ Finalizado! Correção aplicada. O cartão SD está pronto para uso."
