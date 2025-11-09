#!/bin/bash
set -e

cleanup_chroot_mounts() {
  echo "🧹 Limpando mounts temporários e dispositivos loop..."
  sudo umount "$MNT_DIR/dev" "$MNT_DIR/proc" "$MNT_DIR/sys" 2>/dev/null || true
  sudo umount "$MNT_DIR" 2>/dev/null || true
  sudo kpartx -dv "$LOOP_DEV" 2>/dev/null || true
  sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
}

# === Verificação de dependências ===
REQUIRED_TOOLS=(wget xz gunzip lsblk dd parted wipefs qemu-img qemu-user-static sudo kpartx mount chroot debootstrap)
MISSING_TOOLS=()

for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    MISSING_TOOLS+=("$tool")
  fi
done

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
  echo "🔧 Instalando dependências: ${MISSING_TOOLS[*]}"
  sudo apt update
  for tool in "${MISSING_TOOLS[@]}"; do
    sudo apt install -y "$tool" || echo "❌ Erro ao instalar '$tool'. Continue manualmente se necessário."
  done
fi

# Mensagem de alerta para ferramentas ainda ausentes
for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    echo "⚠️ Atenção: ferramenta '$tool' ainda não está disponível no sistema."
  fi
done
# ...existing code...

BASE_DIR="$HOME/Downloads/rpi3-images"

# === Lista de distros ===
declare -A distros
declare -A urls
declare -A files
declare -A extra_steps
declare -A slugs

# Debian-based
# (ID 1-5)
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
extra_steps[3]="install_gui"
slugs[3]="ubuntu-server-arm64"

distros[4]="Raspberry Pi OS Lite (armhf)"
urls[4]="https://downloads.raspberrypi.org/raspios_lite_armhf_latest"
files[4]="raspios_lite.img"
extra_steps[4]="install_gui"
slugs[4]="raspios-lite-armhf"

distros[5]="Debian 12 ARM64"
urls[5]="https://ftp.debian.org/debian/dists/bookworm/main/installer-arm64/current/images/netboot/SD-card-images/firmware.bookworm.arm64.img.gz"
files[5]="firmware.bookworm.arm64.img"
extra_steps[5]="install_gui"
slugs[5]="debian-12-arm64"

distros[6]="Raspberry Pi LITE (arm64)"
urls[6]="https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2025-05-13/2025-05-13-raspios-bookworm-arm64-lite.img.xz"
files[6]="2025-05-13-raspios-bookworm-arm64-lite.img"
extra_steps[6]=""
slugs[6]="raspios-lite-arm64"

distros[7]="Raspberry Pi FULL (arm64)"
urls[7]="https://downloads.raspberrypi.org/raspios_full_arm64/images/raspios_full_arm64-2025-05-13/2025-05-13-raspios-bookworm-arm64-full.img.xz"
files[7]="2025-05-13-raspios-bookworm-arm64-full.img"
extra_steps[7]=""
slugs[7]="raspios-full-arm64"

distros[8]="Raspberry Pi (arm64)"
urls[8]="https://downloads.raspberrypi.org/raspios_arm64/images/raspios_arm64-2025-05-13/2025-05-13-raspios-bookworm-arm64.img.xz"
files[8]="2025-05-13-raspios-bookworm-arm64.img"
extra_steps[8]=""
slugs[8]="raspios-arm64"

# Red Hat-based
# (ID 6-8)
distros[9]="AlmaLinux 9 Minimal (arm64)"
urls[9]="https://repo.almalinux.org/almalinux/9/raspberrypi/images/AlmaLinux-9-RaspberryPi-latest.aarch64.raw.xz"
files[9]="AlmaLinux-9-RaspberryPi-latest.aarch64.raw"
extra_steps[9]="warn_unsupported_boot install_gui firstboot_setup"
slugs[9]="almalinux-9-arm64"

distros[10]="AlmaLinux 10 GNOME (arm64)"
urls[10]="https://repo.almalinux.org/almalinux/10/raspberrypi/images/AlmaLinux-10-RaspberryPi-GNOME-latest.aarch64.raw.xz"
files[10]="AlmaLinux-10-RaspberryPi-GNOME-latest.aarch64.raw"
extra_steps[10]=""
slugs[10]="almalinux-10-arm64"

distros[11]="Fedora IoT 40 Minimal (arm64)"
urls[11]="https://mirrors.dotsrc.org/fedora-alt/iot/40/IoT/aarch64/images/Fedora-IoT-raw-40-20240422.3.aarch64.raw.xz"
files[11]="Fedora-IoT-raw-40-20240422.3.aarch64.raw"
extra_steps[11]="install_gui"
slugs[11]="fedora-iot-40-arm64"

distros[12]="Fedora 42 KDE (arm64)"
urls[12]="https://download.fedoraproject.org/pub/fedora/linux/releases/42/KDE/aarch64/images/Fedora-KDE-Desktop-Disk-42-1.1.aarch64.raw.xz"
files[12]="Fedora-KDE-Desktop-Disk-42-1.1.aarch64.raw"
extra_steps[12]=""
slugs[12]="fedora-kde-42-arm64"

# ⚠️ EOL - CentOS 7 Minimal Legacy
distros[13]="CentOS 7 Minimal Legacy (armhf) — ⚠️ EOL, apenas para validação"
urls[13]="https://mirror.chpc.utah.edu/pub/centos-altarch/7/isos/armhfp/CentOS-Userland-7-armv7hl-RaspberryPI-Minimal-2009-sda.raw.xz"
files[13]="CentOS-Userland-7-armv7hl-RaspberryPI-Minimal-2009-sda.raw"
extra_steps[13]="warn_unsupported_boot"
slugs[13]="centos7-Minimal-legacy-armhf"

# ⚠️ EOL - CentOS 7 GNOME Legacy
distros[14]="CentOS 7 GNOME Legacy (armhf) — ⚠️ EOL, apenas para validação"
urls[14]="https://mirror.chpc.utah.edu/pub/centos-altarch/7/isos/armhfp/CentOS-Userland-7-armv7hl-RaspberryPI-GNOME-2009-sda.raw.xz"
files[14]="CentOS-Userland-7-armv7hl-RaspberryPI-GNOME-2009-sda.raw"
extra_steps[14]="warn_unsupported_boot"
slugs[14]="centos7-GNOME-legacy-armhf"

# === Seleção ===
echo "=== Escolha a distribuição para instalar no Raspberry Pi 3 ==="
echo "\n--- Distribuições baseadas em Debian ---"
for i in 1 2 3 4 5 6 7 8; do
  echo "[$i] ${distros[$i]}"
done

echo "\n--- Distribuições baseadas em Red Hat ---"
for i in 9 10 11 12 13 14; do
  echo "[$i] ${distros[$i]}"
done

read -rp "\nDigite o número da distribuição desejada: " escolha

DISTRO="${distros[$escolha]}"
URL="${urls[$escolha]}"
FILE="${files[$escolha]}"
TASK="${extra_steps[$escolha]}"
SLUG="${slugs[$escolha]}"

DISTRO_DIR="$BASE_DIR/$SLUG"
UNPACKED_DIR="$DISTRO_DIR/unpacked"
LOG_DIR="$DISTRO_DIR/logs"

if [[ -d "$DISTRO_DIR" ]]; then
  read -rp "Deseja limpar e baixar novamente a imagem (s/n)? " limpar
  if [[ "$limpar" == "s" ]]; then
    echo "🧹 Limpando diretório $DISTRO_DIR..."
    rm -rf "$DISTRO_DIR"
  fi
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
base_name="$(basename "$URL")"
file_path="$DISTRO_DIR/$base_name"
out_name="${FILE}"
out_path="$UNPACKED_DIR/$out_name"

if [[ ! -f "$file_path" ]]; then
  echo "🔽 Baixando $base_name..."
  curl -L --progress-bar  "$URL" -o "$file_path"
fi

echo "Validando arquivos $out_path"

if [[ -f "$out_path" ]]; then
  read -rp "⚠️ Arquivo descompactado já existe. Deseja descompactar novamente? (s/n): " desfazer
  if [[ "$desfazer" == "s" ]]; then
    echo "🧹 Limpando $UNPACKED_DIR..."
    rm -rf "$UNPACKED_DIR"
    mkdir -p "$UNPACKED_DIR"
  fi
elif [[ -d "$UNPACKED_DIR" ]]; then
  echo "🧹 Limpando diretório de descompactação $UNPACKED_DIR..."
  rm -rf "$UNPACKED_DIR"
  mkdir -p "$UNPACKED_DIR"
else
  mkdir -p "$UNPACKED_DIR"
  echo "📂 Criando diretório de descompactação: $UNPACKED_DIR"
fi

if [[ ! -f "$out_path" ]]; then
  echo "📦 Descompactando para $UNPACKED_DIR..."
  case "$file_path" in
    *.xz)
      xz -dc "$file_path" > "$out_path"
      ;;
    *.gz)
      gunzip -c "$file_path" > "$out_path"
      ;;
    *.zip)
      unzip -o "$file_path" -d "$UNPACKED_DIR"
      # Corrige o nome do arquivo descompactado, se necessário
      out_path="$(find "$UNPACKED_DIR" -name '*.img' | head -n1)"
      ;;
    *.qcow2)
      echo "🔁 Convertendo .qcow2 para .img..."
      if ! command -v qemu-img >/dev/null 2>&1; then
        echo "📦 Instalando qemu-utils para conversão..."
        sudo apt-get update && sudo apt-get install -y qemu-utils
      fi
      qemu-img convert -O raw "$file_path" "$out_path"
      ;;
    *)
      cp "$file_path" "$out_path"
      ;;
  esac
fi

FILE="$out_path"

# === Menu interface gráfica se necessário ===
if [[ "$TASK" == *"install_gui"* ]]; then
  echo "🎨 A imagem não contém interface gráfica. Deseja instalar uma?"
  echo "[1] XFCE"
  echo "[2] LXQt"
  echo "[3] MATE"
  echo "[4] GNOME Desktop" 
  read -rp "Digite o número da interface desejada: " gui_choice
  case "$gui_choice" in
    1) GUI_PACKAGE="xfce4";;
    2) GUI_PACKAGE="lxqt";;
    3) GUI_PACKAGE="mate-desktop-environment";;
    4) GUI_PACKAGE="GNOME Desktop";;
    *) echo "❌ Opção inválida."; exit 1;;
  esac

  echo "⚙️ Interface escolhida: $GUI_PACKAGE"
  echo "📦 Instalando interface na imagem (etapa posterior via chroot)"

  # Montar imagem e preparar chroot para instalar
  LOOP_DEV=$(sudo losetup --show -Pf "$FILE")
  MAP_PARTS=$(sudo kpartx -av "$LOOP_DEV" | awk '/add/ {print $3}')
  ROOT_PART="/dev/mapper/${MAP_PARTS##*$'\n'}"
  MNT_DIR="$DISTRO_DIR/mnt"
  mkdir -p "$MNT_DIR"
  sudo mount "$ROOT_PART" "$MNT_DIR"

  sudo mount --bind /dev "$MNT_DIR/dev"
  sudo mount --bind /proc "$MNT_DIR/proc"
  sudo mount --bind /sys "$MNT_DIR/sys"
  sudo cp /etc/resolv.conf "$MNT_DIR/etc/resolv.conf"

  # Copiar emulador ARM (qemu) para dentro do chroot
  if [[ ! -f "$MNT_DIR/usr/bin/qemu-aarch64-static" ]]; then
    echo "📦 Copiando emulador ARM para chroot..."
    sudo cp /usr/bin/qemu-aarch64-static "$MNT_DIR/usr/bin/"
  fi

 echo "📦 Instalando $GUI_PACKAGE via chroot..."

# Verifica qual gerenciador de pacotes está disponível no sistema dentro do chroot
PKG_MANAGER=""
if sudo chroot "$MNT_DIR" command -v apt &>/dev/null; then
  PKG_MANAGER="apt"
elif sudo chroot "$MNT_DIR" command -v dnf &>/dev/null; then
  PKG_MANAGER="dnf"
elif sudo chroot "$MNT_DIR" command -v yum &>/dev/null; then
  PKG_MANAGER="yum"
else
  echo "❌ Nenhum gerenciador de pacotes compatível encontrado na imagem."
  cleanup_chroot_mounts
  exit 1
fi

# Executa o comando de instalação apropriado
 echo "📦 Executando comando de instalacao via chroot local $MNT_DIR"
case "$PKG_MANAGER" in
  apt)
    sudo chroot "$MNT_DIR" bash -c "apt update && apt install -y $GUI_PACKAGE"
    ;;
  dnf)
    # Detecta grupo para XFCE se for o caso
    if [[ "$GUI_PACKAGE" == "xfce4" ]]; then
      sudo chroot "$MNT_DIR" dnf groupinstall -y "Xfce Desktop" \
	|| { echo "❌ Erro durante instalação  gui $GUI_PACKAGE. Limpando..."; cleanup_chroot_mounts; exit 1; }
      # sudo chroot "$MNT_DIR" dnf install -y @xfce-desktop-environment lightdm
      # sudo chroot "$MNT_DIR" dnf install -y xfce* lightdm xorg-x11-server-Xorg
      # sudo chroot "$MNT_DIR" systemctl set-default graphical.target
      # sudo chroot "$MNT_DIR" systemctl enable lightdm
    elif [[ "$GUI_PACKAGE" == "GNOME Desktop" ]]; then
      sudo chroot "$MNT_DIR" dnf groupinstall -y "GNOME Desktop" \
	|| { echo "❌ Erro durante instalação  gui $GUI_PACKAGE. Limpando..."; cleanup_chroot_mounts; exit 1; }
    else
      sudo chroot "$MNT_DIR" dnf install -y "$GUI_PACKAGE" \
	|| { echo "❌ Erro durante instalação  gui $GUI_PACKAGE. Limpando..."; cleanup_chroot_mounts; exit 1; }
    fi
    ;;
  yum)
    # Para imagens mais antigas (CentOS, etc)
    if [[ "$GUI_PACKAGE" == "xfce4" ]]; then
      sudo chroot "$MNT_DIR" yum groupinstall -y "Xfce Desktop" \
	|| { echo "❌ Erro durante instalação gui $GUI_PACKAGE. Limpando..."; cleanup_chroot_mounts; exit 1; }
    else
      sudo chroot "$MNT_DIR" yum install -y "$GUI_PACKAGE" \
	|| { echo "❌ Erro durante instalação gui $GUI_PACKAGE. Limpando..."; cleanup_chroot_mounts; exit 1; }
    fi
    ;;
esac

echo "✅ Interface gráfica instalada com sucesso com $PKG_MANAGER."


  cleanup_chroot_mounts
  echo "✅ Interface gráfica instalada com sucesso."
fi

# === Setup de firstboot se necessário ===
if [[ "$TASK" == *"firstboot_setup"* ]]; then
  echo "🔧 Preparando imagem para criação de usuário na primeira inicialização..."

  LOOP_DEV=$(sudo losetup --show -Pf "$FILE")
  sudo kpartx -av "$LOOP_DEV"
  sleep 2

  ROOT_PART="/dev/mapper/$(basename "$LOOP_DEV")p2"
  MNT_DIR="$DISTRO_DIR/mnt"
  mkdir -p "$MNT_DIR"
  sudo mount "$ROOT_PART" "$MNT_DIR"

  INIT_SCRIPT="$MNT_DIR/usr/local/bin/firstboot-user.sh"
  SERVICE_FILE="$MNT_DIR/etc/systemd/system/firstboot-user.service"

  echo "📜 Criando script de criação de usuário..."
  sudo tee "$INIT_SCRIPT" > /dev/null <<'EOF'
#!/bin/bash
echo "👤 Criando novo usuário:"
read -p "Novo nome de usuário: " newuser
adduser "$newuser"
passwd "$newuser"
echo "✅ Usuário criado com sucesso."
rm -f /etc/systemd/system/multi-user.target.wants/firstboot-user.service
rm -f /usr/local/bin/firstboot-user.sh
EOF

  sudo chmod +x "$INIT_SCRIPT"

  echo "📄 Criando serviço systemd..."
  sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Criação de usuário na primeira inicialização
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/firstboot-user.sh
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

  echo "🔗 Habilitando serviço para primeiro boot manualmente..."
  sudo mkdir -p "$MNT_DIR/etc/systemd/system/multi-user.target.wants"
  sudo ln -sf ../firstboot-user.service "$MNT_DIR/etc/systemd/system/multi-user.target.wants/firstboot-user.service"

  sudo umount "$MNT_DIR"
  sudo kpartx -dv "$LOOP_DEV"
  sudo losetup -d "$LOOP_DEV"
  echo "✅ Serviço configurado para criar usuário na primeira inicialização."
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

# === Apagar partições existentes e preparar SD ===
echo "🧼 Limpando partições existentes em $sd..."
sudo umount ${sd}?* || true
sudo wipefs -a "$sd"
sudo parted -s "$sd" mklabel msdos
sync && sleep 2

# === Gravar imagem ===
echo "💾 Gravando imagem em $sd..."
sudo dd if="$FILE" of="$sd" bs=4M status=progress conv=fsync
sync && sleep 5

# === Correções específicas ===
if [[ "$TASK" == *"fix_config_txt"* ]]; then
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

if [[ "$TASK" == *"warn_unsupported_boot"* ]]; then
  echo "⚠️ AVISO: Esta imagem pode não inicializar corretamente no Raspberry Pi 3."
  echo "         Verifique se o bootloader, firmware e overlays são compatíveis."
  echo "         Ajustes manuais podem ser necessários."
fi

echo ""
echo "✅ Cartão preparado com '$DISTRO'."
echo "📁 Tudo salvo em: $DISTRO_DIR"
echo "📃 Log: $LOG_FILE"
echo "📝 Script finalizado às $(date)"

