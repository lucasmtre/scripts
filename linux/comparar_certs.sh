#!/usr/bin/env bash
set -euo pipefail

# comparar_certs.sh
# Compara certificados X.509 por fingerprint (SHA-256) e exibe campos úteis.
# Modo 1: --files <cert1> <cert2>
# Modo 2: --server <host:porta> --local <cert.pem> [--servername <SNI>] [--starttls smtp|imap|pop3]
#
# Saída: mostra Subject, Issuer, Serial, Validade e Fingerprint dos dois
# Exit code: 0 = iguais; 1 = diferentes; 2 = erro de uso.

usage() {
  cat <<'USO'
Uso:
  # Comparar dois arquivos (PEM ou DER)
  ./comparar_certs.sh --files cert_servidor.pem meu_certificado.pem

  # Conectar no servidor e comparar com um arquivo local
  ./comparar_certs.sh --server example.com:443 --local meu_certificado.pem --servername example.com

  # Conectar com STARTTLS (ex.: SMTP)
  ./comparar_certs.sh --server smtp.exemplo.com:25 --local meu_certificado.pem --starttls smtp --servername smtp.exemplo.com

Opções:
  --files <certA> <certB>         Compara diretamente dois arquivos
  --server <host:porta>           Busca o certificado ao vivo via openssl s_client
  --local <arquivo.pem>           Certificado local para comparar
  --servername <SNI>              SNI a enviar (recomendado para HTTPS com virtual hosts)
  --starttls <proto>              smtp | imap | pop3 (usa STARTTLS antes de ler o cert)
  -h | --help                     Mostra esta ajuda
USO
}

die() { echo "Erro: $*" >&2; exit 2; }

# --- Helpers ---

tmpfiles=()
cleanup() {
  for f in "${tmpfiles[@]:-}"; do [ -f "$f" ] && rm -f "$f" || true; done
}
trap cleanup EXIT

# Converte para PEM se o arquivo estiver em DER
to_pem_if_needed() {
  local in="$1"
  # Se já contiver BEGIN CERTIFICATE, retorna como está
  if grep -q "BEGIN CERTIFICATE" "$in" 2>/dev/null; then
    echo "$in"
    return 0
  fi
  # Tenta converter como DER -> PEM
  local out
  out="$(mktemp)"
  tmpfiles+=("$out")
  if openssl x509 -inform der -in "$in" -out "$out" >/dev/null 2>&1; then
    echo "$out"
    return 0
  fi
  # Talvez seja uma cadeia PKCS7/DER: tenta extrair
  if openssl pkcs7 -inform der -in "$in" -print_certs -out "$out" >/dev/null 2>&1; then
    echo "$out"
    return 0
  fi
  # Falhou: devolve original (para erro adiante)
  echo "$in"
}

fingerprint_sha256() {
  local pem="$1"
  openssl x509 -in "$pem" -noout -fingerprint -sha256 \
    | awk -F= '{print toupper(gensub(":","", "g", $2))}'
}

print_info() {
  local title="$1" pem="$2"
  echo "======== $title ========"
  openssl x509 -in "$pem" -noout -subject -issuer -serial -dates
  echo "SHA256 Fingerprint: $(fingerprint_sha256 "$pem")"
  echo
}

extract_leaf_from_s_client() {
  # Lê da stdin e extrai APENAS o 1º certificado (leaf)
  awk '
    /-----BEGIN CERTIFICATE-----/ {p=1}
    p {print}
    /-----END CERTIFICATE-----/ {exit}
  '
}

fetch_server_cert_leaf() {
  local hostport="$1" sni="${2:-}" starttls="${3:-}"
  local out
  out="$(mktemp)"
  tmpfiles+=("$out")

  # Monta o comando s_client
  # -showcerts para garantir que a cadeia venha completa (vamos extrair o primeiro)
  # Uso de input vazio para não travar na conexão
  if [ -n "$starttls" ]; then
    if [ -n "$sni" ]; then
      echo | openssl s_client -connect "$hostport" -servername "$sni" -showcerts -starttls "$starttls" 2>/dev/null \
        | extract_leaf_from_s_client > "$out"
    else
      echo | openssl s_client -connect "$hostport" -showcerts -starttls "$starttls" 2>/dev/null \
        | extract_leaf_from_s_client > "$out"
    fi
  else
    if [ -n "$sni" ]; then
      echo | openssl s_client -connect "$hostport" -servername "$sni" -showcerts 2>/dev/null \
        | extract_leaf_from_s_client > "$out"
    else
      echo | openssl s_client -connect "$hostport" -showcerts 2>/dev/null \
        | extract_leaf_from_s_client > "$out"
    fi
  fi

  # Sanidade
  if ! grep -q "BEGIN CERTIFICATE" "$out"; then
    die "não foi possível obter o certificado do servidor em $hostport"
  fi

  echo "$out"
}

# --- Parse args ---
mode=""
certA=""
certB=""
hostport=""
local_cert=""
sni=""
starttls=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --files)
      mode="files"
      certA="${2:-}"; certB="${3:-}"; shift 2 || true
      ;;
    --server)
      mode="server"
      hostport="${2:-}"; shift
      ;;
    --local)
      local_cert="${2:-}"; shift
      ;;
    --servername)
      sni="${2:-}"; shift
      ;;
    --starttls)
      starttls="${2:-}"; shift
      ;;
    -h|--help)
      usage; exit 0;;
    *)
      # Se ainda não temos certB após --files, talvez seja o segundo arg
      if [ "$mode" = "files" ] && [ -z "$certB" ] && [ -n "${1:-}" ]; then
        certB="$1"
      else
        echo "Argumento desconhecido: $1" >&2
        usage; exit 2
      fi
      ;;
  esac
  shift || true
done

# --- Execução conforme modo ---

if [ "$mode" = "files" ]; then
  [ -n "$certA" ] && [ -n "$certB" ] || { usage; exit 2; }
  [ -f "$certA" ] || die "arquivo não encontrado: $certA"
  [ -f "$certB" ] || die "arquivo não encontrado: $certB"

  pemA="$(to_pem_if_needed "$certA")"
  pemB="$(to_pem_if_needed "$certB")"

  print_info "Certificado A ($certA)" "$pemA"
  print_info "Certificado B ($certB)" "$pemB"

  fpA="$(fingerprint_sha256 "$pemA")"
  fpB="$(fingerprint_sha256 "$pemB")"

  if [ "$fpA" = "$fpB" ]; then
    echo "✅ Iguais (fingerprint SHA-256 coincide)"
    exit 0
  else
    echo "❌ Diferentes (fingerprint SHA-256 não coincide)"
    exit 1
  fi

elif [ "$mode" = "server" ]; then
  [ -n "$hostport" ] && [ -n "$local_cert" ] || { usage; exit 2; }
  [ -f "$local_cert" ] || die "arquivo não encontrado: $local_cert"

  pem_local="$(to_pem_if_needed "$local_cert")"
  pem_srv="$(fetch_server_cert_leaf "$hostport" "$sni" "$starttls")"

  print_info "Servidor ($hostport${sni:+, SNI=$sni})" "$pem_srv"
  print_info "Local ($local_cert)" "$pem_local"

  fpsrv="$(fingerprint_sha256 "$pem_srv")"
  fploc="$(fingerprint_sha256 "$pem_local")"

  if [ "$fpsrv" = "$fploc" ]; then
    echo "✅ Iguais (fingerprint SHA-256 coincide)"
    exit 0
  else
    echo "❌ Diferentes (fingerprint SHA-256 não coincide)"
    # Tentativa opcional: verificar se o local é CA que valida o do servidor
    echo
    echo "Tentando verificar se o certificado LOCAL é uma CA que valida o do servidor..."
    if openssl verify -CAfile "$pem_local" "$pem_srv" 2>/dev/null | grep -q ": OK$"; then
      echo "ℹ️  O certificado local parece validar o do servidor (atua como CA/intermediário)."
    else
      echo "ℹ️  O certificado local NÃO valida o do servidor como CA/intermediário."
    fi
    exit 1
  fi
else
  usage; exit 2
fi
