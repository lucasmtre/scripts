#!/bin/bash
set -e

# === Registro de log ===
LOG_FILE="$HOME/instalacao_rpi_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -i "$LOG_FILE") 2>&1

# === Verificação e instalação de dependências ===
echo "🔍 Verificando e instalando dependências necessárias..."

REQUIRED_TOOLS=(curl xzcat lsblk dd wipefs parted udevadm umount zstd udisksctl lsof)
MISSING_TOOLS=()

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
    echo "⚙️ Instalando pacotes ausentes: ${MISSING_TOOLS[*]}"
    sudo apt update
    sudo apt install -y "${MISSING_TOOLS[@]}"
else
    echo "✅ Todas as dependências já estão instaladas."
fi

# === Diretório base ===
BASE_DIR="$HOME/Downloads/rpi5"

declare -A distros
declare -A urls
declare -A files
declare -A slugs

# === Lista de distros ===
distros[1]="Ubuntu Server 24.04 LTS (ARM64) [Recomendado]"
urls[1]="https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04-preinstalled-server-arm64+raspi.img.xz"
files[1]="ubuntu-24.04-preinstalled-server-arm64+raspi.img"
slugs[1]="ubuntu-server-24.04"

distros[2]="DietPi (ARM64) [Super leve]"
urls[2]="https://dietpi.com/downloads/images/DietPi_RPi_arm64.img.xz"
files[2]="DietPi_RPi_arm64.img"
slugs[2]="dietpi-arm64"

distros[3]="Raspberry Pi OS Lite (Bookworm ARM64)"
urls[3]="https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2024-03-15/2024-03-15-raspios-bookworm-arm64-lite.img.xz"
files[3]="2024-03-15-raspios-bookworm-arm64-lite.img"
slugs[3]="raspios-lite-arm64"

distros[4]="Fedora IoT 42 (ARM64)"
urls[4]="https://download.fedoraproject.org/pub/alt/iot/42/IoT/aarch64/images/Fedora-IoT-raw-42-20250605.0.aarch64.raw.xz"
files[4]="Fedora-IoT-raw-42-20250605.0.aarch64.raw"
slugs[4]="fedora-iot-42"

# === Escolha da distro ===
echo ""
echo "📦 Escolha a distribuição para instalar no Raspberry Pi 5:"
for i in $(printf "%s\n" "${!distros[@]}" | sort -n); do
    echo "  [$i] ${distros[$i]}"
done

read -rp "Digite o número da distro: " escolha
[[ -n "${distros[$escolha]}" ]] || { echo "❌ Escolha inválida."; exit 1; }

DISTRO_NAME="${distros[$escolha]}"
DISTRO_URL="${urls[$escolha]}"
IMAGE_FILE="${files[$escolha]}"
SLUG="${slugs[$escolha]}"

DISTRO_DIR="$BASE_DIR/$SLUG"
DOWNLOAD_DIR="$DISTRO_DIR/downloads"
EXTRACT_DIR="$DISTRO_DIR/extracted"
					   

echo ""
echo "📁 Diretório da distro: $DISTRO_DIR"

mkdir -p "$DOWNLOAD_DIR" "$EXTRACT_DIR"

# === Gerenciar download ===
ARCHIVE_NAME="$(basename "$DISTRO_URL")"
ARCHIVE_PATH="$DOWNLOAD_DIR/$ARCHIVE_NAME"

if [[ -f "$ARCHIVE_PATH" ]]; then
    echo "📦 Já existe um arquivo baixado em: $ARCHIVE_PATH"
    read -rp "❓ Deseja apagar e baixar novamente? (sim/não): " REBAIXAR
    if [[ "$REBAIXAR" == "sim" ]]; then
        echo "🧹 Limpando pasta de download..."
        rm -rf "$DOWNLOAD_DIR"
        mkdir -p "$DOWNLOAD_DIR"
    fi
fi

cd "$DOWNLOAD_DIR"
if [[ ! -f "$ARCHIVE_NAME" ]]; then
    echo "⬇️  Baixando $DISTRO_NAME..."
    curl -L -o "$ARCHIVE_NAME" "$DISTRO_URL"
    file "$ARCHIVE_PATH" | grep -qi "HTML" && {
        echo "❌ ERRO: O download falhou. O arquivo parece ser uma página HTML, não uma imagem compactada."
        exit 1
    }
else
    echo "✅ Usando imagem já baixada."
fi

# === Gerenciar extração ===
cd "$EXTRACT_DIR"
if [[ -f "$EXTRACT_DIR/$IMAGE_FILE" ]]; then
    echo "📦 Já existe uma imagem extraída: $EXTRACT_DIR/$IMAGE_FILE"
    read -rp "❓ Deseja apagar e extrair novamente? (sim/não): " REEXTRAIR
    if [[ "$REEXTRAIR" == "sim" ]]; then
        echo "🧹 Limpando pasta de extração..."
        rm -rf "$EXTRACT_DIR"
        mkdir -p "$EXTRACT_DIR"
    fi
fi

cd "$EXTRACT_DIR"
if [[ ! -f "$IMAGE_FILE" ]]; then
    echo "📦 Extraindo imagem: $ARCHIVE_PATH"
    echo "🛠 Tipo de extensão detectada: ${ARCHIVE_NAME##*.}"

    if [[ "$ARCHIVE_NAME" == *.xz ]]; then
	echo "🗜 Descompactando com xzcat..."
	if ! xzcat "$ARCHIVE_PATH" > "$IMAGE_FILE"; then
		echo "❌ ERRO: Falha ao descompactar com xzcat. O arquivo pode não estar compactado com .xz corretamente."
		exit 1
	fi
    elif [[ "$ARCHIVE_NAME" == *.zst ]]; then
	echo "🗜 Descompactando com zstd..."
	if ! zstd -d "$ARCHIVE_PATH" -o "$IMAGE_FILE"; then
		echo "❌ ERRO: Falha ao descompactar com zstd."
		exit 1
	fi
    else
	echo "📝 Arquivo não compactado. Copiando diretamente..."
	cp "$ARCHIVE_PATH" "$IMAGE_FILE"
    fi
	echo "✅ Extração concluída: $IMAGE_FILE"
else
    echo "✅ Usando imagem já extraída."
fi

# === Seleção do dispositivo SD ===
echo ""
echo "💾 Dispositivos disponíveis:"
lsblk -d -o NAME,SIZE,MODEL | grep -E '^sd|^mmcblk'
echo ""
read -rp "Digite o caminho do cartão SD (ex: /dev/sdX ou /dev/mmcblk0): " SD_DEVICE
[[ -b "$SD_DEVICE" ]] || { echo "❌ Dispositivo inválido."; exit 1; }

read -rp "⚠️ Tem certeza que deseja APAGAR todas as partições e gravar a imagem? (sim/não): " CONFIRMA
[[ "$CONFIRMA" == "sim" ]] || { echo "❌ Cancelado."; exit 1; }

# === Desmontar partições montadas ===
echo "📤 Tentando desmontar partições de $SD_DEVICE..."
for part in $(lsblk -ln "$SD_DEVICE" | awk '{print $1}' | grep -v "$(basename "$SD_DEVICE")"); do
    mountpoint="/dev/$part"
    echo "⏏️  Desmontando $mountpoint..."
    if ! sudo umount "$mountpoint" 2>/dev/null; then
        echo "⚠️ Aviso: não foi possível desmontar $mountpoint (pode já estar desmontado)"
    fi
done
echo "✅ Desmontagem concluída."

# === Função para liberar o dispositivo com segurança ===
echo "🛑 Forçando liberação do dispositivo com udisksctl..."
if command -v udisksctl &>/dev/null; then
    echo "🔁 Executando: udisksctl unmount e power-off..."
    sudo udisksctl unmount -b "$SD_DEVICE" 2>/dev/null || true
    sudo udisksctl power-off -b "$SD_DEVICE" 2>/dev/null || true

    echo "🔄 Aguardando reinicialização automática do dispositivo..."
    sleep 5
    echo "📡 Recarregando informações com udevadm..."
    sudo udevadm trigger
    sudo udevadm settle
fi

if ! lsblk | grep -q "$(basename "$SD_DEVICE")"; then
    echo "❌ ERRO: O dispositivo $SD_DEVICE não reapareceu após power-off."
    echo "🔌 Tente desconectar e reconectar o cartão SD, depois reinicie o script."
    exit 1
fi


# === Limpar partições (com fallback) ===
echo "🧹 Limpando partições de $SD_DEVICE..."
if ! sudo wipefs --all "$SD_DEVICE"; then
    echo "⚠️ Tentando forçar unmount com padrão ${SD_DEVICE}*..."
    sudo umount "${SD_DEVICE}"* 2>/dev/null || true
    sleep 2
    sudo wipefs --all "$SD_DEVICE" || {
        echo "❌ ERRO: Ainda não foi possível limpar o dispositivo com wipefs."
        echo "💡 Reinicie o sistema ou desconecte/reconecte o SD manualmente."
        exit 1
    }
fi
sudo parted "$SD_DEVICE" --script mklabel msdos
sudo udevadm settle

# === Gravar imagem ===
echo "💽 Gravando imagem no cartão SD..."
sudo dd if="$EXTRACT_DIR/$IMAGE_FILE" of="$SD_DEVICE" bs=4M status=progress conv=fsync
sync
echo "✅ Gravação concluída com sucesso."

# === Final ===
echo ""
echo "🚀 Remova o cartão SD com segurança e insira no Raspberry Pi 5."
echo "ℹ️ Sistema instalado: $DISTRO_NAME"
if [[ "$DISTRO_NAME" == *"Ubuntu Server"* ]]; then
    echo ""
    echo "💡 Dica: após o boot, instale uma interface gráfica leve se quiser:"
    echo "  XFCE → sudo apt install -y xfce4 lightdm"
    echo "  LXQt → sudo apt install -y lxqt sddm"
    echo "  MATE → sudo apt install -y ubuntu-mate-desktop"
fi

