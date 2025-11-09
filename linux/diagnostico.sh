#!/bin/bash

ARQUIVO="relatorio_diagnostico.txt"
> "$ARQUIVO"

echo "🔍 Iniciando diagnóstico do sistema..." | tee -a "$ARQUIVO"

# Verifica e instala os pacotes necessários
PACOTES=(htop iotop lm-sensors smartmontools)

echo -e "\n📦 Verificando dependências..." | tee -a "$ARQUIVO"
for pkg in "${PACOTES[@]}"; do
    if ! command -v "$pkg" &>/dev/null; then
        echo "🔧 Instalando $pkg..." | tee -a "$ARQUIVO"
        sudo apt-get update && sudo apt-get install -y "$pkg"
    else
        echo "✅ $pkg já instalado." | tee -a "$ARQUIVO"
    fi
done

echo -e "\n📅 Data/Hora: $(date)" | tee -a "$ARQUIVO"
echo "----------------------------------------" | tee -a "$ARQUIVO"

# Hostname e Kernel
echo -e "\n📌 Hostname e Kernel:" | tee -a "$ARQUIVO"
uname -a | tee -a "$ARQUIVO"

# Uptime
echo -e "\n⏱️ Uptime:" | tee -a "$ARQUIVO"
uptime | tee -a "$ARQUIVO"

# Espaço em disco
echo -e "\n💽 Espaço em disco (df -h):" | tee -a "$ARQUIVO"
df -h | tee -a "$ARQUIVO"

# Uso de memória
echo -e "\n🧠 Uso de memória (RAM e SWAP):" | tee -a "$ARQUIVO"
free -h | tee -a "$ARQUIVO"

# Processos que mais usam memória
echo -e "\n📈 Top 10 processos por uso de memória:" | tee -a "$ARQUIVO"
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 11 | tee -a "$ARQUIVO"

# Processos que mais usam CPU
echo -e "\n⚙️ Top 10 processos por uso de CPU:" | tee -a "$ARQUIVO"
ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%cpu | head -n 11 | tee -a "$ARQUIVO"

# Maiores diretórios na raiz
echo -e "\n📂 Maiores diretórios na raiz (top 10):" | tee -a "$ARQUIVO"
du -h --max-depth=1 / 2>/dev/null | sort -hr | head -n 10 | tee -a "$ARQUIVO"

# Últimos erros do sistema
echo -e "\n🚨 Últimos 20 erros do sistema (journalctl):" | tee -a "$ARQUIVO"
journalctl -p 3 -xb | tail -n 20 | tee -a "$ARQUIVO"

# Serviços lentos no boot
echo -e "\n🐌 Serviços mais lentos no boot:" | tee -a "$ARQUIVO"
systemd-analyze blame | head -n 10 | tee -a "$ARQUIVO"

# Temperatura
echo -e "\n🌡️ Temperatura do sistema (sensors):" | tee -a "$ARQUIVO"
sensors | tee -a "$ARQUIVO"

# S.M.A.R.T. do disco principal
DISCO="/dev/$(lsblk -dno NAME | head -n 1)"
echo -e "\n🧪 Status S.M.A.R.T. do disco (${DISCO}):" | tee -a "$ARQUIVO"
sudo smartctl -H "$DISCO" | tee -a "$ARQUIVO"

# Uso do disco (iotop)
echo -e "\n🔄 Top processos por uso de disco (snapshot do iotop):" | tee -a "$ARQUIVO"
sudo iotop -b -n 5 | head -n 20 | tee -a "$ARQUIVO"

# Load average
echo -e "\n📊 Carga média do sistema:" | tee -a "$ARQUIVO"
cat /proc/loadavg | tee -a "$ARQUIVO"

echo -e "\n✅ Diagnóstico finalizado. Relatório salvo em: $ARQUIVO"
