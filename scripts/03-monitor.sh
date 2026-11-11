#!/usr/bin/env bash
# =============================================================
# Passo Seguro - GS 2026.2 - Operating Systems
# Script 03: monitoramento da infraestrutura
# Mede CPU, memoria e disco, confere a API e o Apache e grava
# alertas no log quando algum limite e ultrapassado.
# Uso:
#   sudo bash scripts/03-monitor.sh --uma-vez   (faz uma medicao e sai)
#   sudo bash scripts/03-monitor.sh             (mede a cada 30 segundos, sem parar)
# =============================================================
set -uo pipefail

# ---------- Variaveis (limites e intervalo) ----------
LIMITE_CPU=80          # % de uso de CPU que gera alerta
LIMITE_MEMORIA=80      # % de uso de memoria que gera alerta
LIMITE_DISCO=80        # % de uso do disco / que gera alerta
INTERVALO=30           # segundos entre uma medicao e outra
URL_SAUDE="http://127.0.0.1/health"     # rota da API, passando pelo Apache
SERVICOS="passo-seguro-api httpd"       # servicos que precisam estar no ar

PASTA_LOG="/var/log/passo-seguro"
LOG="$PASTA_LOG/monitoramento.log"     # todas as medicoes
LOG_ALERTAS="$PASTA_LOG/alertas.log"   # so os alertas

# ---------- So roda como administrador ----------
if [[ $EUID -ne 0 ]]; then
  echo "Rode com sudo: sudo bash scripts/03-monitor.sh"
  exit 1
fi

mkdir -p "$PASTA_LOG"

# ---------- Funcoes de log ----------
log() {
  local nivel="$1"; shift
  local linha
  linha="$(date '+%Y-%m-%d %H:%M:%S') [$nivel] [03-monitor] $*"
  echo "$linha" | tee -a "$LOG"
  if [[ "$nivel" == "ALERTA" ]]; then
    echo "$linha" >> "$LOG_ALERTAS"
    logger -t passo-seguro -p user.warning "$linha"
  fi
}

# ---------- Funcoes de medicao ----------
# CPU: le /proc/stat duas vezes, com 1 segundo de diferenca, e calcula o uso
uso_cpu() {
  local u1 n1 s1 i1 w1 q1 sq1 st1 u2 n2 s2 i2 w2 q2 sq2 st2
  read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
  sleep 1
  read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat
  local ocioso=$(( (i2 + w2) - (i1 + w1) ))
  local total=$(( (u2+n2+s2+i2+w2+q2+sq2+st2) - (u1+n1+s1+i1+w1+q1+sq1+st1) ))
  if (( total == 0 )); then echo 0; return; fi
  echo $(( (100 * (total - ocioso)) / total ))
}

# Memoria: (total - disponivel) / total, lido de /proc/meminfo
uso_memoria() {
  awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {d=$2} END {printf "%d", (t-d)*100/t}' /proc/meminfo
}

# Disco: porcentagem usada da particao principal (/)
uso_disco() {
  df --output=pcent / | tail -1 | tr -dc '0-9'
}

# ---------- Uma rodada de verificacao ----------
verificar() {
  local cpu mem disco alertas=0

  cpu="$(uso_cpu)"
  mem="$(uso_memoria)"
  disco="$(uso_disco)"

  if (( cpu >= LIMITE_CPU )); then
    log ALERTA "CPU em ${cpu}% (limite ${LIMITE_CPU}%)"; alertas=$((alertas+1))
  fi
  if (( mem >= LIMITE_MEMORIA )); then
    log ALERTA "Memoria em ${mem}% (limite ${LIMITE_MEMORIA}%)"; alertas=$((alertas+1))
  fi
  if (( disco >= LIMITE_DISCO )); then
    log ALERTA "Disco em ${disco}% (limite ${LIMITE_DISCO}%)"; alertas=$((alertas+1))
  fi

  for servico in $SERVICOS; do
    if ! systemctl is-active --quiet "$servico"; then
      log ALERTA "Servico $servico fora do ar"; alertas=$((alertas+1))
    fi
  done

  if ! curl -fsS -m 5 "$URL_SAUDE" > /dev/null 2>&1; then
    log ALERTA "API nao respondeu em $URL_SAUDE"; alertas=$((alertas+1))
  fi

  if (( alertas == 0 )); then
    log OK "CPU ${cpu}% | Memoria ${mem}% | Disco ${disco}% | API e Apache no ar"
  else
    log INFO "CPU ${cpu}% | Memoria ${mem}% | Disco ${disco}% | ${alertas} alerta(s)"
  fi
}

# ---------- Execucao ----------
if [[ "${1:-}" == "--uma-vez" ]]; then
  verificar
  exit 0
fi

log INFO "Monitoramento iniciado (a cada ${INTERVALO}s; limites: CPU ${LIMITE_CPU}%, memoria ${LIMITE_MEMORIA}%, disco ${LIMITE_DISCO}%)"
trap 'log INFO "Monitoramento encerrado"; exit 0' SIGTERM SIGINT
while true; do
  verificar
  sleep "$INTERVALO" &
  wait $!
done
