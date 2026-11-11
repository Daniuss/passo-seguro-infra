#!/usr/bin/env bash
# =============================================================
# Passo Seguro - GS 2026.2 - Operating Systems
# Script 01: provisionamento da infraestrutura
# Configura: hostname, IP fixo, DNS, fuso horario e firewall
# Uso: sudo bash scripts/01-infra.sh
# =============================================================
set -euo pipefail

# ---------- Variaveis (ajuste aqui se precisar) ----------
HOSTNAME_NOVO="passo-seguro"
DOMINIO="passo-seguro.local"
INTERFACE_INTERNA="enp0s8"        # placa host-only (liga o Windows a VM)
IP_FIXO="192.168.56.10/24"
INTERFACE_INTERNET="enp0s3"       # placa NAT (da internet a VM)
DNS_SERVIDORES="8.8.8.8,1.1.1.1"
FUSO="America/Sao_Paulo"

PASTA_LOG="/var/log/passo-seguro"
LOG="$PASTA_LOG/provisionamento.log"

# ---------- So roda como administrador ----------
if [[ $EUID -ne 0 ]]; then
  echo "Rode com sudo: sudo bash scripts/01-infra.sh"
  exit 1
fi

# ---------- Log de auditoria ----------
# Cada linha registra data, hora, nivel, script e quem executou.
# Grava no arquivo de log e tambem no journal do sistema (logger).
mkdir -p "$PASTA_LOG"
log() {
  local nivel="$1"; shift
  local linha
  linha="$(date '+%Y-%m-%d %H:%M:%S') [$nivel] [01-infra] [usuario=${SUDO_USER:-root}] $*"
  echo "$linha" | tee -a "$LOG"
  logger -t passo-seguro "$linha"
}
trap 'log ERRO "Falha na linha $LINENO. Provisionamento interrompido."' ERR

log INFO "===== Inicio do provisionamento da infraestrutura ====="

# ---------- 1. Hostname ----------
log INFO "Definindo o hostname como $HOSTNAME_NOVO"
hostnamectl set-hostname "$HOSTNAME_NOVO"

# ---------- 2. Resolucao de nome local (/etc/hosts) ----------
IP_SEM_MASCARA="${IP_FIXO%/*}"
if ! grep -q "$DOMINIO" /etc/hosts; then
  echo "$IP_SEM_MASCARA $DOMINIO $HOSTNAME_NOVO" >> /etc/hosts
  log INFO "Adicionado ao /etc/hosts: $IP_SEM_MASCARA $DOMINIO $HOSTNAME_NOVO"
else
  log INFO "/etc/hosts ja tinha $DOMINIO. Nada a fazer."
fi

# ---------- 3. Fuso horario ----------
log INFO "Definindo o fuso horario como $FUSO"
timedatectl set-timezone "$FUSO"

# ---------- 4. IP fixo na placa interna ----------
CON_INTERNA="$(nmcli -g GENERAL.CONNECTION device show "$INTERFACE_INTERNA")"
if [[ -z "$CON_INTERNA" ]]; then
  CON_INTERNA="passo-seguro-interna"
  log INFO "Criando a conexao $CON_INTERNA para $INTERFACE_INTERNA"
  nmcli con add type ethernet ifname "$INTERFACE_INTERNA" con-name "$CON_INTERNA"
fi
log INFO "Configurando IP fixo $IP_FIXO na conexao '$CON_INTERNA' ($INTERFACE_INTERNA)"
nmcli con mod "$CON_INTERNA" \
  ipv4.method manual \
  ipv4.addresses "$IP_FIXO" \
  ipv4.never-default yes \
  connection.autoconnect yes
nmcli con up "$CON_INTERNA" > /dev/null

# ---------- 5. DNS na placa de internet ----------
CON_INTERNET="$(nmcli -g GENERAL.CONNECTION device show "$INTERFACE_INTERNET")"
log INFO "Configurando DNS $DNS_SERVIDORES na conexao '$CON_INTERNET' ($INTERFACE_INTERNET)"
nmcli con mod "$CON_INTERNET" ipv4.dns "$DNS_SERVIDORES" ipv4.ignore-auto-dns yes
nmcli con up "$CON_INTERNET" > /dev/null

# ---------- 6. Firewall ----------
log INFO "Ativando o firewall e liberando SSH (22) e HTTP (80)"
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh > /dev/null
firewall-cmd --permanent --add-service=http > /dev/null
firewall-cmd --reload > /dev/null

# ---------- 7. Conferencia ----------
log INFO "----- Conferencia -----"
log INFO "Hostname: $(hostnamectl --static)"
log INFO "IP interno: $(ip -4 -br addr show "$INTERFACE_INTERNA" | awk '{print $3}')"
log INFO "Servicos liberados no firewall: $(firewall-cmd --list-services)"

if ping -c 1 -W 3 8.8.8.8 > /dev/null 2>&1; then
  log OK "Internet funcionando (ping 8.8.8.8)"
else
  log FALHA "Sem internet (ping 8.8.8.8 falhou)"
fi

if getent hosts github.com > /dev/null; then
  log OK "DNS funcionando (github.com resolvido)"
else
  log FALHA "DNS nao resolveu github.com"
fi

if getent hosts "$DOMINIO" > /dev/null; then
  log OK "Nome local funcionando ($DOMINIO -> $IP_SEM_MASCARA)"
else
  log FALHA "Nome local $DOMINIO nao resolvido"
fi

log INFO "===== Fim do provisionamento da infraestrutura ====="
