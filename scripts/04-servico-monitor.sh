#!/usr/bin/env bash
# =============================================================
# Passo Seguro - GS 2026.2 - Operating Systems
# Script 04: monitoramento como servico tolerante a falhas
# Instala o monitor (script 03) como servico do systemd, que
# liga junto com a VM e reinicia sozinho se for derrubado.
# Tambem configura a rotacao dos logs (logrotate).
# Uso: sudo bash scripts/04-servico-monitor.sh
# =============================================================
set -euo pipefail

# ---------- Variaveis ----------
DIR_SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
ORIGEM_MONITOR="$DIR_SCRIPTS/03-monitor.sh"
DESTINO_MONITOR="/usr/local/bin/passo-seguro-monitor"
SERVICO_MONITOR="passo-seguro-monitor"
CONF_LOGROTATE="/etc/logrotate.d/passo-seguro"

PASTA_LOG="/var/log/passo-seguro"
LOG="$PASTA_LOG/provisionamento.log"

# ---------- So roda como administrador ----------
if [[ $EUID -ne 0 ]]; then
  echo "Rode com sudo: sudo bash scripts/04-servico-monitor.sh"
  exit 1
fi

# ---------- Log de auditoria ----------
mkdir -p "$PASTA_LOG"
log() {
  local nivel="$1"; shift
  local linha
  linha="$(date '+%Y-%m-%d %H:%M:%S') [$nivel] [04-servico] [usuario=${SUDO_USER:-root}] $*"
  echo "$linha" | tee -a "$LOG"
  logger -t passo-seguro "$linha"
}
trap 'log ERRO "Falha na linha $LINENO. Provisionamento interrompido."' ERR

log INFO "===== Inicio da instalacao do monitoramento como servico ====="

# ---------- 1. Instalar o script de monitoramento ----------
if [[ ! -f "$ORIGEM_MONITOR" ]]; then
  log ERRO "Nao encontrei $ORIGEM_MONITOR"
  exit 1
fi
install -m 755 "$ORIGEM_MONITOR" "$DESTINO_MONITOR"
log INFO "Monitor instalado em $DESTINO_MONITOR"

# ---------- 2. Servico systemd tolerante a falhas ----------
# Restart=always       -> se o monitor cair ou for morto, o systemd religa
# RestartSec=5         -> espera 5 segundos antes de religar
# StartLimitIntervalSec=0 -> nunca desiste de religar, mesmo com varias quedas
cat > "/etc/systemd/system/$SERVICO_MONITOR.service" <<EOF
[Unit]
Description=Passo Seguro - Monitoramento de CPU, memoria, disco e servicos
After=network-online.target passo-seguro-api.service httpd.service
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=$DESTINO_MONITOR
Restart=always
RestartSec=5
SyslogIdentifier=$SERVICO_MONITOR

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "$SERVICO_MONITOR" > /dev/null 2>&1
systemctl restart "$SERVICO_MONITOR"
log INFO "Servico $SERVICO_MONITOR ativado (liga com a VM e reinicia sozinho se cair)"

# ---------- 3. Rotacao dos logs ----------
# Todo dia o log atual e arquivado e comprimido; guarda os ultimos 7 dias.
cat > "$CONF_LOGROTATE" <<EOF
$PASTA_LOG/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF
log INFO "Rotacao de logs configurada em $CONF_LOGROTATE (diaria, guarda 7 dias)"

# ---------- 4. Conferencia ----------
log INFO "----- Conferencia -----"
sleep 3
log INFO "Servico do monitor: $(systemctl is-active "$SERVICO_MONITOR") | liga com a VM: $(systemctl is-enabled "$SERVICO_MONITOR")"

if systemctl is-active --quiet "$SERVICO_MONITOR"; then
  log OK "Monitor rodando como servico"
else
  log FALHA "Monitor nao esta rodando"
fi

if logrotate -d "$CONF_LOGROTATE" > /dev/null 2>&1; then
  log OK "Configuracao do logrotate valida"
else
  log FALHA "Configuracao do logrotate com erro"
fi

log INFO "Ultima medicao: $(tail -1 "$PASTA_LOG/monitoramento.log")"
log INFO "===== Fim da instalacao do monitoramento como servico ====="
