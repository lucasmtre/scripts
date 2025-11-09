#!/bin/bash

# Nome do arquivo de log onde tudo será registrado
LOGFILE="correcao_sistema.log"
> "$LOGFILE"

# Função auxiliar para logar no terminal e no arquivo simultaneamente
log() {
    echo -e "$1" | tee -a "$LOGFILE"
}

log "📋 Início da correção - $(date)"
log "-------------------------------------------"

# 1. Instalar dependências necessárias para diagnóstico e melhoria de desempenho
# - smartmontools: verifica saúde do disco (S.M.A.R.T.)
# - lm-sensors: permite leitura de temperatura
# - i8kutils: ativa suporte à leitura e controle de fan em notebooks Dell
# - preload: acelera abertura de aplicativos frequentemente usados
# - zram-tools: ativa swap comprimido na RAM, melhora desempenho em máquinas com uso intenso de memória
log "\n📦 Instalando dependências..."
PACOTES=(smartmontools lm-sensors i8kutils preload zram-tools)

for pkg in "${PACOTES[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        log "🔧 Instalando: $pkg"
        sudo apt-get update && sudo apt-get install -y "$pkg" &>> "$LOGFILE"
    else
        log "✅ $pkg já está instalado."
    fi
done

# 2. Remover o serviço canonical-livepatch
# Esse serviço aplica atualizações no kernel sem reinicializar, mas você não está usando ativamente
# Ele gerava erros nos logs e pode ser removido sem risco
log "\n🧹 Removendo canonical-livepatch..."
if snap list | grep -q canonical-livepatch; then
    sudo snap remove canonical-livepatch &>> "$LOGFILE"
    log "✅ canonical-livepatch removido com sucesso."
else
    log "ℹ️ canonical-livepatch já não está instalado."
fi

# 3. Limpeza de logs antigos
# Reduz o uso de disco em /var/log mantendo apenas os últimos 7 dias
log "\n🧾 Limpando logs antigos (/var/log)..."
sudo journalctl --vacuum-time=7d &>> "$LOGFILE"
log "✅ Logs antigos removidos (mantido apenas últimos 7 dias)."

# 4. Limpeza do cache do apt
# Remove pacotes já instalados que ocupam espaço em /var/cache/apt/archives
log "\n🗑️ Limpando cache de pacotes do APT..."
sudo apt clean &>> "$LOGFILE"
log "✅ Cache APT limpo."

# 5. Limpeza de arquivos temporários antigos
# Remove arquivos com mais de 7 dias em /var/tmp
log "\n🧹 Limpando /var/tmp..."
sudo find /var/tmp -type f -mtime +7 -exec rm -f {} \; &>> "$LOGFILE"
log "✅ Arquivos temporários antigos removidos."

# 6. Remoção de snaps antigos desabilitados
# Esses snaps ocupam espaço em /snap e não estão mais em uso
log "\n📦 Removendo snaps antigos (desabilitados)..."
snap list --all | awk '/disabled/{print $1, $3}' | while read snapname revision; do
    sudo snap remove "$snapname" --revision="$revision" &>> "$LOGFILE"
done
log "✅ Snaps antigos removidos."

# 7. Desativar o GNOME Tracker
# Este indexador estava usando até 175% de CPU no seu sistema
# Ele serve para buscar arquivos no sistema, mas é desnecessário para a maioria dos usuários
log "\n📂 Desativando GNOME Tracker (indexador)..."
gsettings set org.freedesktop.Tracker.Miner.Files enable-monitors false &>> "$LOGFILE"
tracker3 reset --hard &>> "$LOGFILE"
log "✅ Tracker desativado com sucesso."

# 8. Ativar suporte ao controle de cooler Dell
# Seu cooler estava parado (fan1: 0 RPM), isso pode causar throttling térmico
# Aqui ativamos o módulo i8k que permite a leitura/controlador do cooler Dell
log "\n❄️ Ativando suporte ao cooler Dell (i8k)..."
echo "options i8k force=1" | sudo tee /etc/modprobe.d/i8k.conf &>> "$LOGFILE"
sudo modprobe i8k &>> "$LOGFILE"
log "✅ Módulo i8k ativado."

# 9. Verificar o estado do disco principal via S.M.A.R.T.
# Usa o smartctl para garantir que o disco /dev/sda está saudável
log "\n💽 Verificando S.M.A.R.T. de /dev/sda..."
sudo smartctl -H /dev/sda | tee -a "$LOGFILE"

# Finalização
log "\n✅ Correção finalizada às: $(date)"
log "🗂️ Relatório salvo em: $LOGFILE"
