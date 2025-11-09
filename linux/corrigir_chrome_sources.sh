#!/bin/bash
set -e

# =============================================================
# Script de correção de repositórios no Ubuntu
# Corrige problemas com o arquivo ubuntu.sources duplicado ou corrompido
# Corrige ou adiciona o repositório do Google Chrome com chave GPG válida
# Atualiza o sistema após as correções
# Remove backups antigos ao final, incluindo os do dia atual
# Compatível com Ubuntu 18.04 até 24.04
# =============================================================

echo "🔎 [0/8] Verificando e instalando dependências básicas..."

REQUIRED_CMDS=("curl" "wget" "gpg" "awk" "apt")

# Verifica e instala dependências
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "📦 Instalando dependência ausente: $cmd"
        sudo apt update
        sudo apt install -y "$cmd"
    fi
done

# Garante que o suporte a HTTPS está disponível no apt
if ! dpkg -s apt-transport-https &>/dev/null; then
    echo "📦 Instalando apt-transport-https..."
    sudo apt install -y apt-transport-https
fi

# =============================================================
echo ""
echo "🔧 [1/8] Corrigindo repositório do Google Chrome..."

# Se o repositório ainda não estiver configurado, adiciona chave e fonte
if ! grep -q "dl.google.com" /etc/apt/sources.list.d/google-chrome.list 2>/dev/null; then
    sudo mkdir -p /etc/apt/keyrings

    # Testa se a chave está acessível antes de instalar
    if curl -s --head --fail https://dl.google.com/linux/linux_signing_key.pub >/dev/null; then
        echo "🔑 Baixando chave pública da Google..."
        wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | \
            sudo gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg
    else
        echo "❌ Falha ao baixar chave GPG. Verifique conexão com a internet."
        exit 1
    fi

    echo "🔗 Adicionando repositório do Google Chrome..."
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | \
        sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
else
    echo "ℹ️ Repositório do Chrome já configurado."
fi

# =============================================================
echo ""
echo "📦 [2/8] Atualização de pacotes será feita após verificar repositórios..."

# =============================================================
echo ""
echo "💻 [3/8] Verificando se o Google Chrome está instalado..."

# Se não estiver instalado, instala
if ! command -v google-chrome >/dev/null; then
    echo "💡 Chrome não instalado. Instalando agora..."
    sudo apt install -y google-chrome-stable
else
    echo "✅ Google Chrome já está presente no sistema."
fi

# =============================================================
echo ""
echo "🩺 [4/8] Verificando integridade do arquivo ubuntu.sources..."

SOURCE_FILE="/etc/apt/sources.list.d/ubuntu.sources"

# Verifica existência e validade do arquivo ubuntu.sources
if [ -f "$SOURCE_FILE" ]; then
    echo "📁 Arquivo encontrado. Testando..."
    if ! apt update 2>&1 | grep -q "Malformed stanza"; then
        echo "✅ Arquivo ubuntu.sources está válido."
    else
        echo "⚠️ Estrutura corrompida detectada. Iniciando correção segura..."

        TODAY=$(date +%Y%m%d)
        BACKUP_EXISTENTE=$(ls /etc/apt/sources.list.d/ubuntu.sources.bkp.${TODAY}* 2>/dev/null || true)

        # Cria backup apenas se ainda não existir um do mesmo dia
        if [ -z "$BACKUP_EXISTENTE" ]; then
            BACKUP_FILE="${SOURCE_FILE}.bkp.$(date +%Y%m%d-%H%M%S)"
            sudo cp "$SOURCE_FILE" "$BACKUP_FILE"
            echo "📂 Backup criado: $BACKUP_FILE"
        else
            echo "📦 Backup de hoje já existente:"
            echo "$BACKUP_EXISTENTE"
        fi

        echo "🛑 Desativando arquivo corrompido..."
        sudo mv "$SOURCE_FILE" "${SOURCE_FILE}.disabled"

        echo "🧾 Criando novo ubuntu.list com repositórios padrão..."
        cat <<EOF | sudo tee /etc/apt/sources.list.d/ubuntu.list > /dev/null
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
EOF
    fi
else
    echo "ℹ️ Nenhum arquivo ubuntu.sources encontrado. Nada a corrigir."
fi

# =============================================================
echo ""
echo "📦 [5/8] Atualizando lista de pacotes após correções..."
sudo apt update

# =============================================================
echo ""
echo "🔍 [6/8] Verificando origem da instalação do Chrome..."

# Verifica se o Chrome está associado ao repositório oficial
ORIGEM=$(apt policy google-chrome-stable | grep "Instalado de:" || echo "N/A")

if echo "$ORIGEM" | grep -q "dl.google.com"; then
    echo "$ORIGEM"
    echo "✅ Chrome corretamente vinculado ao repositório da Google."
else
    echo "$ORIGEM"
    echo "⚠️ Chrome não vinculado ao repositório oficial. Reinstalando para corrigir..."
    sudo apt install --reinstall -y google-chrome-stable
fi

# =============================================================
echo ""
echo "🧹 [7/8] Limpando todos os backups de ubuntu.sources após execução bem-sucedida..."

# Remove todos os arquivos de backup da pasta, inclusive os do dia atual
sudo find /etc/apt/sources.list.d/ -name "ubuntu.sources.bkp.*" -type f -exec rm -f {} \;
echo "✅ Todos os backups de ubuntu.sources removidos com sucesso."

# =============================================================
echo ""
echo "🏁 [8/8] Script finalizado com sucesso!"
echo "✅ Sistema verificado, corrigido e limpo com segurança."
