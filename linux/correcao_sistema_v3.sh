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

# Exibe o espaço em disco antes da limpeza
log "\n📊 Espaço livre antes da limpeza:"
df -h / | tee -a "$LOGFILE"

# 1. Instalar ferramentas essenciais de diagnóstico e performance
# - smartmontools: diagnóstico S.M.A.R.T. do disco
# - lm-sensors: leitura de sensores de temperatura
# - i8kutils: controle do cooler Dell
# - preload: pré-carregamento de apps usados com frequência
# - zram-tools: swap na RAM para performance em uso intensivo
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

# 2. Remover o Snap do canonical-livepatch se ainda existir
# Ele aplica patches ao kernel em tempo real, mas causa erros e não está em uso ativo
log "\n🧹 Removendo canonical-livepatch..."
if snap list | grep -q canonical-livepatch; then
    sudo snap remove canonical-livepatch &>> "$LOGFILE"
    log "✅ canonical-livepatch removido com sucesso."
else
    log "ℹ️ canonical-livepatch já não está instalado."
fi

# 3. Limpeza de logs do journal com mais de 7 dias
# Isso reduz uso de espaço em /var/log
log "\n🧾 Limpando logs antigos (/var/log)..."
sudo journalctl --vacuum-time=7d &>> "$LOGFILE"
log "✅ Logs antigos removidos (mantido apenas últimos 7 dias)."

# 4. Limpeza do cache do APT
# Remove pacotes obsoletos em /var/cache/apt/archives
log "\n🗑️ Limpando cache de pacotes do APT..."
sudo apt clean &>> "$LOGFILE"
log "✅ Cache APT limpo."

# 5. Limpeza de arquivos temporários com mais de 7 dias em /var/tmp
# Evita acúmulo de arquivos esquecidos no sistema
log "\n🧹 Limpando /var/tmp..."
sudo find /var/tmp -type f -mtime +7 -exec rm -f {} \; &>> "$LOGFILE"
log "✅ Arquivos temporários antigos removidos."

# 6. Remover snaps desabilitados (ocupam espaço mesmo sem uso)
# Isso libera espaço em /snap
log "\n📦 Removendo snaps antigos (desabilitados)..."
snap list --all | awk '/disabled/{print $1, $3}' | while read snapname revision; do
    sudo snap remove "$snapname" --revision="$revision" &>> "$LOGFILE"
done
log "✅ Snaps antigos removidos."

# 7. Desativar o GNOME Tracker (indexador de arquivos)
# O tracker3 causava alto uso de CPU no seu sistema
# A desativação é feita conforme a versão detectada (compatível com Ubuntu antigos e novos)
log "\n🔍 Verificando versão do Tracker..."
if command -v tracker3 &>/dev/null; then
    STATUS=$(tracker3 status 2>/dev/null || true)
    if echo "$STATUS" | grep -q "Currently indexed"; then
        log "🔧 Desativando Tracker (versão GNOME moderna)..."
        gsettings set org.freedesktop.Tracker3.Miner.Files index-recursive-directories "[]" &>> "$LOGFILE"
        tracker3 reset --filesystem &>> "$LOGFILE"
        log "✅ Tracker moderno desativado com sucesso."
    else
        log "⚠️ Tracker3 instalado, mas não ativo."
    fi
elif command -v tracker &>/dev/null; then
    log "🔧 Desativando Tracker (versão antiga)..."
    gsettings set org.freedesktop.Tracker.Miner.Files enable-monitors false &>> "$LOGFILE"
    tracker reset --hard &>> "$LOGFILE"
    log "✅ Tracker antigo desativado com sucesso."
else
    log "ℹ️ Nenhuma versão do Tracker detectada."
fi

# 8. Ativar o controle de cooler Dell (i8k)
# Fundamental no seu modelo (Inspiron 7520) para monitoramento e prevenção de superaquecimento
log "\n❄️ Ativando suporte ao cooler Dell (i8k)..."
echo "options i8k force=1" | sudo tee /etc/modprobe.d/i8k.conf &>> "$LOGFILE"
sudo modprobe i8k &>> "$LOGFILE"
log "✅ Módulo i8k ativado."

# 9. Verificar integridade do disco principal
# Usamos smartctl para checar o status de saúde do /dev/sda
log "\n💽 Verificando S.M.A.R.T. de /dev/sda..."
sudo smartctl -H /dev/sda | tee -a "$LOGFILE"

# 10. Exibe espaço após a limpeza para comparação
log "\n📊 Espaço livre depois da limpeza:"
df -h / | tee -a "$LOGFILE"

# Finalização do script
log "\n✅ Correção finalizada às: $(date)"
log "🗂️ Relatório salvo em: $LOGFILE"
