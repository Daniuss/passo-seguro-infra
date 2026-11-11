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
if [[ -d "$DIR_FONTE/.git" ]]; then
  log INFO "Atualizando o codigo da API (git pull)"
  git -C "$DIR_FONTE" fetch --quiet origin "$BRANCH_API"
  git -C "$DIR_FONTE" reset --quiet --hard "origin/$BRANCH_API"
else
  log INFO "Baixando o codigo da API de $REPO_API"
  rm -rf "$DIR_FONTE"
  git clone --quiet --branch "$BRANCH_API" "$REPO_API" "$DIR_FONTE"
fi
log INFO "Versao do codigo: commit $(git -C "$DIR_FONTE" rev-parse --short HEAD)"
 
# ---------- 4. Compilacao ----------
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
log INFO "Compilando a API (dotnet publish)"
rm -rf "$DIR_PUBLICADO"
dotnet publish "$DIR_FONTE/$CAMINHO_CSPROJ" -c Release -o "$DIR_PUBLICADO" > /dev/null
NOME_DLL="$(basename "$CAMINHO_CSPROJ" .csproj).dll"
chown -R "$USUARIO_APP:$USUARIO_APP" "$DIR_PUBLICADO"
log INFO "API compilada em $DIR_PUBLICADO/$NOME_DLL"
 
# ---------- 5. Variaveis de ambiente da API ----------
mkdir -p "$DIR_CONFIG"
cat > "$ARQ_AMBIENTE" <<EOF
ASPNETCORE_URLS=http://127.0.0.1:$PORTA_API
ASPNETCORE_ENVIRONMENT=Production
DOTNET_CLI_TELEMETRY_OPTOUT=1
EOF
chmod 640 "$ARQ_AMBIENTE"
log INFO "Arquivo de ambiente gravado em $ARQ_AMBIENTE"
 
# ---------- 6. Servico systemd da API ----------
cat > "/etc/systemd/system/$SERVICO_API.service" <<EOF
[Unit]
Description=Passo Seguro - API
After=network-online.target
Wants=network-online.target
 
[Service]
User=$USUARIO_APP
WorkingDirectory=$DIR_PUBLICADO
EnvironmentFile=$ARQ_AMBIENTE
ExecStart=/usr/bin/dotnet $DIR_PUBLICADO/$NOME_DLL
Restart=always
RestartSec=5
SyslogIdentifier=$SERVICO_API
 
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "$SERVICO_API" > /dev/null 2>&1
systemctl restart "$SERVICO_API"
log INFO "Servico $SERVICO_API ativado (reinicia sozinho se cair)"
 
# ---------- 7. Apache como porta de entrada (porta 80) ----------
cat > "$CONF_APACHE" <<EOF
# Passo Seguro: o Apache recebe na porta 80 e repassa para a API
ProxyPreserveHost On
ProxyPass        / http://127.0.0.1:$PORTA_API/
ProxyPassReverse / http://127.0.0.1:$PORTA_API/
EOF
# SELinux: permite que o Apache faca conexoes de rede (repasse para a API)
setsebool -P httpd_can_network_connect 1
systemctl enable httpd > /dev/null 2>&1
systemctl restart httpd
log INFO "Apache configurado: porta 80 -> API na porta $PORTA_API"
 
# ---------- 8. Conferencia ----------
log INFO "----- Conferencia -----"
sleep 5
log INFO "Servico da API: $(systemctl is-active "$SERVICO_API")"
log INFO "Servico do Apache: $(systemctl is-active httpd)"
 
if curl -fsS "http://127.0.0.1:$PORTA_API$ROTA_TESTE" > /dev/null; then
  log OK "API respondendo direto na porta $PORTA_API"
else
  log FALHA "API nao respondeu na porta $PORTA_API"
fi
 
if curl -fsS "http://127.0.0.1$ROTA_TESTE" > /dev/null; then
  log OK "API respondendo pelo Apache na porta 80"
else
  log FALHA "Apache nao repassou para a API"
fi
 
log INFO "Acesse do Windows: http://192.168.56.10/"
log INFO "===== Fim do provisionamento da aplicacao ====="
