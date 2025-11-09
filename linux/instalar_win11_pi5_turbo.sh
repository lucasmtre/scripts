#!/usr/bin/env bash
# Instala Windows 11 ARM64 no Raspberry Pi 5 usando WoR-Flasher (modo terminal)
# Suporta: Ubuntu/Debian/Raspberry Pi OS (x86_64 ou ARM)
# Uso:
#   sudo bash instalar_win11_pi5_turbo.sh -d /dev/sdX -l pt-br [-i /caminho/Win11_ARM64.iso]
# Exemplo:
#   sudo bash instalar_win11_pi5_turbo.sh -d /dev/mmcblk0 -l pt-br -i ~/Downloads/Win11_Arm64_25H2.iso

set -euo pipefail

DEVICE=""
WIN_LANG="pt-br"
ISO_PATH=""
WOR_MODE=""

# --- args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device) DEVICE="$2"; shift 2;;
    -l|--lang)   WIN_LANG="$2"; shift 2;;
    -i|--iso)    ISO_PATH="$2"; shift 2;;
    -m|--mode)   WOR_MODE="$2"; shift 2;;
    -h|--help)
      echo "Uso: sudo $0 -d /dev/sdX -l pt-br [-i /caminho/Win11_ARM64.iso] [-m cli|gui]"
      exit 0;;
    *) echo "Arg desconhecido: $1"; exit 1;;
  esac
done

# if [[ $EUID -ne 0 ]]; then
#   echo "Por favor, rode com sudo."
#   exit 1
# fi

if [[ -z "${DEVICE}" ]]; then
  echo "Obrigatório informar o dispositivo destino com -d /dev/sdX (ATENÇÃO: será APAGADO)."
  exit 1
fi

if [[ ! -b "${DEVICE}" ]]; then
  echo "Dispositivo inválido: ${DEVICE}"
  exit 1
fi

# Proteção boba contra acerto no disco do sistema
ROOT_DEV="$(lsblk -no pkname "$(df / | tail -1 | awk '{print $1}')" 2>/dev/null || true)"
if [[ -n "${ROOT_DEV}" && "/dev/${ROOT_DEV}" == "${DEVICE#/dev/}" ]]; then
  echo "ERRO: o dispositivo informado (${DEVICE}) parece ser o DISCO DO SISTEMA. Aborte."
  exit 1
fi

if [[ -n "${WOR_MODE}" ]]; then
  WOR_MODE="$(tr '[:upper:]' '[:lower:]' <<<"${WOR_MODE}")"
fi

if [[ -z "${WOR_MODE}" ]]; then
  echo
  echo "Selecione como deseja rodar o WoR-Flasher:"
  echo "  1) Terminal (CLI automatizado)"
  echo "  2) Interface gráfica (GUI oficial)"
  while true; do
    read -r -p "Digite 1 para CLI ou 2 para GUI: " answer
    case "${answer}" in
      1|cli|CLI)
        WOR_MODE="cli"
        break;;
      2|gui|GUI)
        WOR_MODE="gui"
        break;;
      *) echo "Opção inválida. Tente novamente.";;
    esac
  done
fi

if [[ "${WOR_MODE}" != "cli" && "${WOR_MODE}" != "gui" ]]; then
  echo "Modo inválido: ${WOR_MODE}. Use 'cli' ou 'gui'."
  exit 1
fi

if [[ "${WOR_MODE}" == "gui" ]]; then
  echo "==> Modo selecionado: GUI (interface gráfica)."
else
  echo "==> Modo selecionado: CLI (terminal)."
fi

echo "==> Atualizando pacotes..."
sudo apt-get update -y
sudo apt-get install -y git curl wget aria2 p7zip-full wimtools cabextract chntpw \
                    exfat-fuse exfatprogs ntfs-3g

FLDIR="/home/${USER}/wor-flasher"

# --- Preparar WoR-Flasher --- 
echo "==> Preparando WoR-Flasher em ${FLDIR}..."
if [[ ! -d "${FLDIR}" ]]; then
  echo "==> Clonando WoR-Flasher..."
  git clone https://github.com/Botspot/wor-flasher "${FLDIR}"
else
  echo "==> Atualizando WoR-Flasher..."
  git -C "${FLDIR}" pull --ff-only
fi

# Pasta de downloads/caches do flasher
DL_DIR="/home/${USER}/wor-flasher-files"
mkdir -p "${DL_DIR}"

# (Opcional) Se o usuário fornecer um ISO ARM64 oficial, colocamos na pasta esperada
if [[ -n "${ISO_PATH}" ]]; then
  if [[ ! -f "${ISO_PATH}" ]]; then
    echo "ISO não encontrado: ${ISO_PATH}"
    exit 1
  fi
  echo "==> Preparando ISO informado pelo usuário..."
  mkdir -p "${DL_DIR}/ISOs"
  # Mantém nome original; o flasher detecta e reutiliza para pular o download
  ISO_BASENAME="$(basename "${ISO_PATH}")"
  DEST_ISO="${DL_DIR}/ISOs/${ISO_BASENAME}"
  SRC_REAL="$(realpath "${ISO_PATH}")"
  DEST_REAL="$(realpath -m "${DEST_ISO}")"
  if [[ "${SRC_REAL}" == "${DEST_REAL}" ]]; then
    echo "==> ISO já está no diretório do WoR (${DEST_ISO})."
  elif [[ -f "${DEST_ISO}" ]] && cmp -s "${ISO_PATH}" "${DEST_ISO}"; then
    echo "==> ISO já preparado anteriormente em ${DEST_ISO}; reutilizando arquivo existente."
  else
    echo "==> Copiando ISO para ${DEST_ISO} (pode demorar alguns minutos)..."
    cp --reflink=auto --sparse=auto "${ISO_PATH}" "${DEST_ISO}"
    echo "==> ISO disponível em ${DEST_ISO}"
  fi
  SOURCE_ISO="${DEST_ISO}"
fi

# --- Rodar em modo não interativo (terminal) ---
# O README do WoR-Flasher documenta variáveis de ambiente para automatizar (RUN_MODE, DEVICE, WIN_LANG, etc.)
# e que o script install-wor.sh aceita execução em 'cli' (sem a GUI).
# Também há suporte ao Pi 5 apontado no README.
# Fonte: repo do WoR-Flasher.
# (Se em alguma versão RPI_MODEL=5 não for aceito, faremos fallback para '4' automaticamente.)

set -a
export DL_DIR
export DIRECTORY="${FLDIR}"
export RUN_MODE="${WOR_MODE}"
export DEVICE="${DEVICE}"
export WIN_LANG="${WIN_LANG}"
if [[ -n "${SOURCE_ISO:-}" ]]; then
  export SOURCE_FILE="${SOURCE_ISO}"
  echo "==> Forçando uso da ISO local: ${SOURCE_ISO}"
fi

SD_INFO="$(lsblk -ndo MODEL,SIZE "${DEVICE}" 2>/dev/null | tr -s ' ' | sed 's/^ //')"
if [[ -n "${SD_INFO}" ]]; then
  echo "==> Gravando no dispositivo ${DEVICE} (${SD_INFO})."
else
  echo "==> Gravando no dispositivo ${DEVICE}."
fi


# Detecta se a versão local do script suporta explicitamente o Pi 5; caso não, usa '4' como fallback.
if grep -q "Raspberry Pi 5" "${FLDIR}/README.md" 2>/dev/null; then
  export RPI_MODEL=5 || true
  echo "==> Configurado para Raspberry Pi 5."
else
  export RPI_MODEL=4
  echo "==> Aviso: versão do WoR-Flasher não documenta suporte ao Pi 5; usando RPI_MODEL=4 como fallback."
fi

# Se o dispositivo for >= 25GB vamos instalar "em si mesmo"
# (WoR também cria modo 'recovery' se for menor)
BYTES=$(sudo blockdev --getsize64 "${DEVICE}")
if (( BYTES >= 25000000000 )); then
  export CAN_INSTALL_ON_SAME_DRIVE=1
  echo "==> Dispositivo tem espaço suficiente (>=25GB); habilitando instalação no próprio drive."
else
  export CAN_INSTALL_ON_SAME_DRIVE=0
  echo "==> Dispositivo tem menos de 25GB; instalação no próprio drive desabilitada (será usado como pendrive instalador)."
  echo "==> Dica: use um cartão/SSD >=25GB se quiser instalar o Windows diretamente nele."
fi

# Opcional: forçar sempre Windows 11 (BID dinâmico). O flasher baixa/usa ISO conforme cache.
# Vamos obter o BID mais recente via função do próprio script.
if [[ "${WOR_MODE}" == "gui" ]]; then
  echo "==> Abrindo WoR-Flasher (GUI) para preparar ${DEVICE}..."
  WOR_SCRIPT="${FLDIR}/install-wor-gui.sh"
else
  echo "==> Iniciando WoR-Flasher (terminal) para gravar Windows 11 ARM64 no ${DEVICE}..."
  WOR_SCRIPT="${FLDIR}/install-wor.sh"
  export FORCE_NO_BID=1
fi

if [[ ! -f "${WOR_SCRIPT}" ]]; then
  echo "Script do WoR-Flasher não encontrado em ${WOR_SCRIPT}."
  exit 1
fi

set +a

# Execução principal (o script instala pacotes faltantes, particiona e grava)
"${WOR_SCRIPT}"

echo "==> Concluído!"
echo
echo "Próximos passos:"
echo "1) Remova com segurança a unidade ${DEVICE} e conecte ao Raspberry Pi 5."
echo "2) No primeiro boot, siga o OOBE do Windows 11."
echo "3) Mantenha UEFI/Drivers atualizados (projeto WoR)."
