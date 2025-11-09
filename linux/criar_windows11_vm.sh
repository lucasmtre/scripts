#!/bin/bash

set -e

# ================================
# CONFIGURAÇÕES INICIAIS
# ================================

VM_NAME="Windows11"
ISO_NAME="Win11_24H2_BrazilianPortuguese_x64.iso"
ISO_URL="https://software.download.prss.microsoft.com/dbazure/Win11_24H2_BrazilianPortuguese_x64.iso?t=2eaae2c3-c584-4498-a5cf-f40f00d7f299&P1=1750190858&P2=601&P3=2&P4=CSOWABjDT57a0DH43qhjUCJ1aaskEyLMBH77VjUqrWOvXSw4N49AsAjXNiqud%2bLjcRJnJNhjHUqLUVZB5JwLPcStSbNTMXE5XxYIdjIYiE59yHL9Zz35xqW6CjC%2bEbLEaydM2sDo1SnISZrdDjLlo5mAsiXDKpQ6MPVxk90%2b8kS360b2bCHOpXDL67kTIW6x9nBl8N%2fhbfo89oa%2bXvlnk%2bO3hRPc5Mn0puyWduqWScCzqKTdSP6R%2b18Q3FWimxHavBTDvFxPUC%2b2jpTvDBIhNekMxEBflMo4Vx%2bHFbT6OCWNhvRh00ubL7J6tW0s1eTKU0ve3e5kyJ3NnM2eS%2f011A%3d%3d"
ISO_DIR="$HOME/Downloads"
ISO_PATH="$ISO_DIR/$ISO_NAME"

VM_DIR="$HOME/VirtualBox VMs/$VM_NAME"
DISK_PATH="$VM_DIR/$VM_NAME.vdi"
RAM_MB=8192
CPU_COUNT=4
DISK_SIZE_MB=65536  # 64 GB

# ================================
# FUNÇÃO DE ERRO
# ================================
erro() {
    echo -e "❌ Erro: $1"
    exit 1
}

# ================================
# CRIA PASTA DE DESTINO
# ================================
mkdir -p "$ISO_DIR"

# ================================
# DOWNLOAD DA ISO
# ================================
if [ ! -f "$ISO_PATH" ]; then
    echo "🔽 Baixando a ISO do Windows 11 24H2 para: $ISO_PATH"

    wget --progress=bar:force -O "$ISO_PATH" "$ISO_URL" || erro "Falha ao baixar a ISO. Verifique sua conexão ou gere um novo link no site da Microsoft."

    # Verifica se o arquivo é válido (tamanho mínimo 5 GB)
    if [ ! -s "$ISO_PATH" ] || [ $(stat -c%s "$ISO_PATH") -lt $((5 * 1024 * 1024 * 1024)) ]; then
        rm -f "$ISO_PATH"
        erro "A ISO foi baixada, mas parece estar incompleta ou corrompida. Tente novamente com um novo link."
    fi
else
    echo "✅ ISO já encontrada em: $ISO_PATH"
fi

# ================================
# CRIA A VM
# ================================
echo "⚙️ Criando a máquina virtual '$VM_NAME'..."
VBoxManage createvm --name "$VM_NAME" --ostype "Windows11_64" --register || erro "Não foi possível criar a VM."

VBoxManage modifyvm "$VM_NAME" \
    --memory $RAM_MB \
    --cpus $CPU_COUNT \
    --vram 128 \
    --ioapic on \
    --boot1 dvd --boot2 disk \
    --pae on \
    --audio none \
    --accelerate3d on \
    --nested-hw-virt on || erro "Erro ao configurar a VM."

# ================================
# DISCO
# ================================
echo "💽 Criando disco virtual de $((DISK_SIZE_MB/1024)) GB..."
VBoxManage createhd --filename "$DISK_PATH" --size $DISK_SIZE_MB --format VDI || erro "Erro ao criar o disco."

VBoxManage storagectl "$VM_NAME" --name "SATA Controller" --add sata --controller IntelAHCI
VBoxManage storageattach "$VM_NAME" --storagectl "SATA Controller" --port 0 --device 0 \
    --type hdd --medium "$DISK_PATH"

# ================================
# ISO COMO DVD
# ================================
VBoxManage storagectl "$VM_NAME" --name "IDE Controller" --add ide
VBoxManage storageattach "$VM_NAME" --storagectl "IDE Controller" --port 0 --device 0 \
    --type dvddrive --medium "$ISO_PATH" || erro "Erro ao anexar a ISO."

# ================================
# REDE
# ================================
VBoxManage modifyvm "$VM_NAME" --nic1 nat

# ================================
# FINALIZAÇÃO
# ================================
echo -e "\n✅ Máquina Virtual '$VM_NAME' criada com sucesso!"
echo "👉 Abra o VirtualBox, selecione a VM '$VM_NAME' e inicie para instalar o Windows 11 24H2."
