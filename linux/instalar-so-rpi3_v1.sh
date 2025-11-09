#!/bin/bash
set -e

BASE_DIR="$HOME/Downloads/rpi3-images"

# === Lista de distros ===
declare -A distros
declare -A urls
declare -A files
declare -A extra_steps
declare -A slugs

distros[1]="Ubuntu MATE 22.04 (arm64)"
urls[1]="https://releases.ubuntu-mate.org/22.04/arm64/ubuntu-mate-22.04-desktop-arm64+raspi.img.xz"
files[1]="ubuntu-mate-22.04-desktop-arm64+raspi.img"
extra_steps[1]="fix_config_txt"
slugs[1]="ubuntu-mate-arm64"

distros[2]="Ubuntu MATE 22.04 (armhf)"
urls[2]="https://releases.ubuntu-mate.org/22.04/armhf/ubuntu-mate-22.04-desktop-armhf+raspi.img.xz"
files[2]="ubuntu-mate-22.04-desktop-armhf+raspi.img"
extra_steps[2]=""
slugs[2]="ubuntu-mate-armhf"

distros[3]="Ubuntu Server 22.04 (arm64)"
urls[3]="https://cdimage.ubuntu.com/releases/22.04/release/ubuntu-22.04.5-preinstalled-server-arm64+raspi.img.xz"
files[3]="ubuntu-22.04.5-preinstalled-server-arm64+raspi.img"
extra_steps[3]=""
slugs[3]="ubuntu-server-arm64"

distros[4]="Raspberry Pi OS Lite (armhf)"
urls[4]="https://downloads.raspberrypi.org/raspios_lite_armhf_latest"
files[4]="raspios_lite.img"
extra_steps[4]=""
slugs[4]="raspios-lite-armhf"

distros[5]="Debian 12 ARM64"
urls[5]="https://ftp.debian.org/debian/dists/bookworm/main/installer-arm64/current/images/netboot/SD-card-images/firmware.bookworm.arm64.img.gz"
files[5]="firmware.bookworm.arm64.img"
extra_steps[5]=""
slugs[5]="debian-12-arm64"

distros[6]="AlmaLinux 9 ARM"
urls[6]="https://repo.almalinux.org/almalinux/9/raspberrypi/images/AlmaLinux-9-RaspberryPi-latest.aarch64.raw.xz"
files[6]="AlmaLinux-9-RaspberryPi-latest.aarch64.raw"
extra_steps[6]="unsupported_image_type"
slugs[6]="almalinux-9-arm64"

distros[7]="Fedora IoT 40 (arm64)"
urls[7]="https://download.fedoraproject.org/pub/fedora/linux/releases/40/IoT/aarch64/images/Fedora-IoT-ostree-aarch64-40-1.14-sda.raw.xz"
files[7]="Fedora-IoT-ostree-aarch64-40-1.14-sda.raw"
extra_steps[7]=""
slugs[7]="fedora-iot-40-arm64"

# ⚠️ EOL - CentOS 7 Legacy
distros[8]="CentOS 7 Legacy (armhf) — ⚠️ EOL, apenas para validação"
urls[8]="https://mirror.centos.org/altarch/7/isos/armhfp/CentOS-Userland-7-armv7hl-RaspberryPI-Minimal-2009-sda.raw.xz"
files[8]="CentOS-Userland-7-armv7hl-RaspberryPI-Minimal-2009-sda.raw"
extra_steps[8]=""
slugs[8]="centos7-legacy-armhf"

# === Seleção ===
echo "=== Escolha a distribuição para instalar no Raspberry Pi 3 ==="
for i in "${!distros[@]}"; do
  echo "[$i] ${distros[$i]}"
done

read -rp "Digite o número da distribuição desejada: " escolha

DISTRO="${distros[$escolha]}"
URL="${urls[$escolha]}"
FILE="${files[$escolha]}"
TASK="${extra_steps[$escolha]}"
SLUG="${slugs[$escolha]}"

DISTRO_DIR="$BASE_DIR/$SLUG"
LOG_DIR="$DISTRO_DIR/logs"

read -rp "Deseja limpar e baixar novamente a imagem (s/n)? " limpar
if [[ "$limpar" == "s" ]]; then
  echo "🧹 Limpando diretório $DISTRO_DIR..."
  rm -rf "$DISTRO_DIR"
fi

mkdir -p "$DISTRO_DIR" "$LOG_DIR"
cd "$DISTRO_DIR"

# === Log ===
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/install-rpi3-$TIMESTAMP.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📃 Log: $LOG_FILE"
echo "📂 Diretório da distribuição: $DISTRO_DIR"

# === Baixar e descompactar imagem ===
if [[ "$URL" =~ .xz$ ]]; then
  base_name="$(basename "$URL")"
  if [[ ! -f "$base_name" ]]; then
    echo "🔽 Baixando $base_name..."
    wget -c "$URL"
  fi
  echo "📦 Descompactando imagem..."
  if [[ -f "${base_name%.xz}" ]]; then
    echo "⚠️  O arquivo descompactado ${base_name%.xz} já existe. Pulando descompactação."
  else
    xz -dk "$base_name"
  fi
elif [[ "$URL" =~ .gz$ ]]; then
  base_name="$(basename "$URL")"
  if [[ ! -f "$base_name" ]]; then
    wget -c "$URL"
  fi
  gunzip -k "$base_name"
elif [[ "$URL" =~ raspberrypi\.org ]]; then
  echo "⬇️ Baixando imagem zipada do Raspberry Pi OS..."
  wget -O raspios.zip "$URL"
  unzip -o raspios.zip
  FILE=$(find . -name "*.img" | head -n1)
elif [[ "$URL" =~ .qcow2$ ]]; then
  echo "🔁 A imagem está no formato .qcow2 — convertendo para .img"

  # Verifica e instala o qemu-utils, se necessário
  if ! command -v qemu-img >/dev/null 2>&1; then
    echo "📦 Instalando qemu-utils para conversão..."
    sudo apt-get update && sudo apt-get install -y qemu-utils
  fi

  # Baixa o arquivo .qcow2
  wget -c "$URL" -O "$FILE"

  IMG_FILE="${FILE%.qcow2}.img"
  echo "💡 Convertendo $FILE para $IMG_FILE..."
  qemu-img convert -O raw "$FILE" "$IMG_FILE"
  FILE="$IMG_FILE"
else
  wget -c "$URL" -O "$FILE"
fi

# === Selecionar cartão ===
echo ""
lsblk
echo ""
read -rp "→ Informe o dispositivo do cartão SD (ex: /dev/mmcblk0 ou /dev/sdb): " sd

if [[ ! "$sd" =~ ^/dev/(sd[a-z]|mmcblk[0-9])$ ]]; then
  echo "❌ Dispositivo inválido."
  exit 1
fi

read -rp "⚠️ Todos os dados em $sd serão apagados. Continuar? (s/n): " conf
[[ "$conf" != "s" ]] && { echo "❌ Cancelado."; exit 0; }

echo "💾 Gravando imagem em $sd..."
sudo dd if="$FILE" of="$sd" bs=4M status=progress conv=fsync
sync && sleep 5

# === Correções específicas ===
if [[ "$TASK" == "fix_config_txt" ]]; then
  echo "🔧 Corrigindo config.txt (Ubuntu MATE arm64)..."
  BOOT_PART=$(lsblk -ln -o NAME "$sd" | grep -E 'p1$|1$' | head -n1)
  BOOT_DEV="/dev/$BOOT_PART"
  MOUNT_POINT="$DISTRO_DIR/bootfs"
  mkdir -p "$MOUNT_POINT"
  sudo mount "$BOOT_DEV" "$MOUNT_POINT"
  sudo sed -i 's/^dtoverlay=vc4-kms-v3d/dtoverlay=vc4-fkms-v3d/' "$MOUNT_POINT/config.txt"
  sudo umount "$MOUNT_POINT" || sudo umount -l "$MOUNT_POINT"
  echo "✅ config.txt corrigido."
fi

echo ""
echo "✅ Cartão preparado com '$DISTRO'."
echo "📁 Tudo salvo em: $DISTRO_DIR"
echo "📃 Log: $LOG_FILE"
