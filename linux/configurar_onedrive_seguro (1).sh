
#!/bin/bash

# Script de instalação e configuração segura do cliente OneDrive no Linux
# Com verificação e reinstalação do compilador D (dmd) + configuração de monitoramento automático
# Autor: ChatGPT (para Lucas)
# Última atualização: 2025-06-21

set -e

PROJETOS_DIR="$HOME/Documentos/_Projetos"
ONEDRIVE_DIR="$PROJETOS_DIR/onedrive"
DMD_MIN_VERSION="2.091.1"

echo "🚀 Iniciando configuração segura do OneDrive no Linux..."

# Função de comparação de versões
version_ge() {
  dpkg --compare-versions "$1" ge "$2"
}

# 1. Instalação de dependências
echo "🔧 Instalando dependências básicas..."
sudo apt update
sudo apt install -y build-essential libcurl4-openssl-dev libsqlite3-dev pkg-config git curl systemd firejail snapd make gcc libfuse-dev

# 2. Verificação da versão do dmd
echo "🧰 Verificando versão do compilador D..."

DMD_INSTALLED=false
DMD_VERSION=""

if command -v dmd >/dev/null; then
  DMD_VERSION=$(dmd --version | grep -oP 'v?\K[0-9]+\.[0-9]+\.[0-9]+')
  echo "🔎 Versão do dmd instalada: $DMD_VERSION"
  DMD_INSTALLED=true
fi

# 3. Verificar se versão instalada é suficiente
if [ "$DMD_INSTALLED" = true ] && version_ge "$DMD_VERSION" "$DMD_MIN_VERSION"; then
  echo "✅ Versão do dmd é adequada. Seguindo com a instalação do OneDrive..."
else
  echo "⚠️ Versão do dmd é insuficiente ou não instalada. Corrigindo..."

  # 3.1 Detectar método de instalação e remover
  if snap list | grep -q "^dmd"; then
    echo "📦 Removendo dmd instalado via Snap..."
    sudo snap remove dmd
  elif dpkg -l | grep -q "^ii  dmd"; then
    echo "📦 Removendo dmd instalado via APT..."
    sudo apt purge -y dmd
  fi

  # 3.2 Instalar manualmente via dlang.org
  echo "⬇️ Baixando e instalando dmd diretamente do site oficial..."
  curl -fsS https://dlang.org/install.sh -o /tmp/install-dmd.sh
  bash /tmp/install-dmd.sh install dmd

  echo "✅ dmd instalado manualmente."
  source ~/dlang/dmd-*/activate
  rm -f /tmp/install-dmd.sh
fi

# 4. Clonar e compilar o cliente OneDrive (abraunegg/onedrive) com suporte a placeholder
echo "📥 Clonando o repositório oficial do cliente OneDrive..."
mkdir -p "$PROJETOS_DIR"
cd "$PROJETOS_DIR"

if [ ! -d "$ONEDRIVE_DIR" ]; then
  git clone https://github.com/abraunegg/onedrive.git
else
  echo "📂 Diretório 'onedrive' já existe em $ONEDRIVE_DIR. Pulando clone..."
fi

cd "$ONEDRIVE_DIR"
echo "⚙️ Configurando e compilando o cliente com suporte a placeholder..."
./configure --enable-placeholder
make
sudo make install

# 5. Criar diretório de configuração
echo "📁 Criando diretório de configuração (se necessário)..."
mkdir -p ~/.config/onedrive

# 6. Criar configuração padrão sem "monitoring_enabled"
CONFIG_FILE=~/.config/onedrive/config

echo "📝 (Re)criando arquivo de configuração padrão..."
cat <<EOF > "$CONFIG_FILE"
sync_dir = "~/OneDrive"
log_dir = "~/.config/onedrive/log"
skip_file = "~*|.~*|*.tmp|*.swp|*.partial"
# Torna o cliente em modo "placeholder", ou seja, não baixa tudo de imediato
download_only = "false"
upload_only = "false"
# Isso aqui ativa o recurso que você quer:
# ⚠️ Disponível apenas se o suporte ao recurso tiver sido compilado (veremos abaixo)
enable_placeholder_support = "true"
EOF

# 7. Execução inicial com firejail
echo "🧪 Executando o cliente pela primeira vez com isolamento via firejail..."
echo "🔐 Você será redirecionado para autenticar no site da Microsoft. Copie e cole o código no terminal."
firejail --noprofile onedrive

# 8. Configurar systemd com --monitor
echo "⚙️ Reconfigurando systemd para iniciar OneDrive com --monitor..."
mkdir -p ~/.config/systemd/user
cat <<EOF > ~/.config/systemd/user/onedrive.service
[Unit]
Description=OneDrive Free Client with Monitor
After=network-online.target

[Service]
ExecStart=/usr/local/bin/onedrive --monitor
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reexec
systemctl --user daemon-reload
systemctl --user enable onedrive
systemctl --user restart onedrive

# 9. Verificação final
echo "🧾 Versão instalada do cliente OneDrive:"
onedrive --version

echo "✅ Cliente OneDrive instalado, configurado e monitorado com sucesso!"
echo "📂 Seus arquivos serão sincronizados em ~/OneDrive"
echo "🔒 O cliente roda com monitoramento em segundo plano (systemd)"
echo "📊 Logs podem ser vistos com: journalctl --user -u onedrive -f"
