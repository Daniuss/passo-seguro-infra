#!/usr/bin/env bash
# =============================================================
# Passo Seguro - GS 2026.2 - Operating Systems
# Script 02: provisionamento da aplicacao
# Instala dependencias, baixa e compila a API, sobe a API como
# servico (systemd) e publica pelo Apache na porta 80.
# Uso: sudo bash scripts/02-app.sh
# =============================================================
set -euo pipefail

# ---------- Variaveis (troque aqui quando a API oficial chegar) ----------
REPO_API="https://github.com/Daniuss/passo-seguro-infra.git"
BRANCH_API="main"
CAMINHO_CSPROJ="api-teste/PassoSeguro.Api/PassoSeguro.Api.csproj"   # caminho dentro do repositorio
VERSAO_DOTNET="8.0"
PORTA_API="5000"                                         # porta interna da API
ROTA_TESTE="/health"                                     # rota usada para conferir se a API responde

USUARIO_APP="passoseguro"           # usuario de sistema que roda a API
DIR_BASE="/opt/passo-seguro"
DIR_FONTE="$DIR_BASE/fonte"         # codigo baixado do GitHub
DIR_PUBLICADO="$DIR_BASE/app"       # versao compilada que roda
DIR_CONFIG="/etc/passo-seguro"
ARQ_AMBIENTE="$DIR_CONFIG/api.env"  # variaveis de ambiente da API
SERVICO_API="passo-seguro-api"
CONF_APACHE="/etc/httpd/conf.d/passo-seguro.conf"

PASTA_LOG="/var/log/passo-seguro"
LOG="$PASTA_LOG/provisionamento.log"

# ---------- So roda como administrador ----------
if [[ $EUID -ne 0 ]]; then
  echo "Rode com sudo: sudo bash scripts/02-app.sh"
  exit 1
fi

# ---------- Log de auditoria ----------
mkdir -p "$PASTA_LOG"
log() {
  local nivel="$1"; shift
  local linha
  linha="$(date '+%Y-%m-%d %H:%M:%S') [$nivel] [02-app] [usuario=${SUDO_USER:-root}] $*"
  echo "$linha" | tee -a "$LOG"
  logger -t passo-seguro "$linha"
}
trap 'log ERRO "Falha na linha $LINENO. Provisionamento interrompido."' ERR

log INFO "===== Inicio do provisionamento da aplicacao ====="

# ---------- 1. Dependencias ----------
log INFO "Instalando dependencias: .NET SDK $VERSAO_DOTNET, git, Apache (httpd)"
dnf install -y "dotnet-sdk-$VERSAO_DOTNET" git httpd > /dev/null
log INFO "Versao do .NET instalada: $(dotnet --version)"

# ---------- 2. Usuario de sistema ----------
if ! id "$USUARIO_APP" > /dev/null 2>&1; then
  useradd --system --no-create-home --shell /sbin/nologin "$USUARIO_APP"
  log INFO "Usuario de sistema $USUARIO_APP criado (sem login)"
else
  log INFO "Usuario $USUARIO_APP ja existe. Nada a fazer."
fi

# ---------- 3. Codigo da API ----------
mkdir -p "$DIR_BASE"
if
