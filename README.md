Passo Seguro – Infraestrutura Linux

Global Solution 2026.2 · CitizenTech · Operating Systems FIAP · Engenharia de Software · 3ESPZ

Integrantes
Nome	RM
Gabriel Danius	555747
Caio Rossini	555084
Giulia Rocha	558084
Carlos Eduardo	556785
Sobre o projeto

O Passo Seguro é uma plataforma de registro e priorização de problemas de acessibilidade urbana em São Paulo (calçadas danificadas, rampas obstruídas, semáforos sem sinal sonoro, entre outros).

Este repositório contém a infraestrutura Linux que hospeda a API do Passo Seguro. Todo o ambiente é preparado por scripts Bash, sem configuração manual: rede, DNS, firewall, instalação de dependências, compilação e publicação da API, monitoramento de recursos com alertas, serviços tolerantes a falhas e logs de auditoria.

Arquitetura
 Windows (navegador)
        │  http://192.168.56.10
        ▼
┌──────────────── VM AlmaLinux 10 (hostname: passo-seguro) ────────────────┐
│                                                                          │
│  Firewall (firewalld): só SSH (22) e HTTP (80) liberados                 │
│        │                                                                 │
│        ▼                                                                 │
│  Apache (httpd) na porta 80 ──repassa──▶ API .NET em 127.0.0.1:5000      │
│                                          serviço: passo-seguro-api       │
│                                                                          │
│  Monitor (serviço: passo-seguro-monitor)                                 │
│   a cada 30 s: CPU, memória, disco, API e Apache ──▶ logs e alertas      │
│                                                                          │
│  Logs: /var/log/passo-seguro/  +  journal do sistema                     │
└──────────────────────────────────────────────────────────────────────────┘

A API escuta só em 127.0.0.1 (dentro da VM). O acesso externo passa sempre pelo Apache, na porta 80.

Ambiente
Item	Configuração
Virtualizador	Oracle VirtualBox
Sistema operacional	AlmaLinux 10.2 (Lavender Lion)
Memória	2 GB
Processador	1 núcleo
Disco	8 GB + 10 GB unidos por LVM (partição / com 16 GB)
Placa de rede 1	NAT: acesso à internet (enp0s3)
Placa de rede 2	Host-only: acesso do Windows à VM (enp0s8, IP fixo 192.168.56.10)
Estrutura do repositório
passo-seguro-infra/
├── scripts/
│   ├── 01-infra.sh            # rede, DNS, IP fixo, hostname, fuso e firewall
│   ├── 02-app.sh              # dependências, compilação e publicação da API
│   ├── 03-monitor.sh          # monitoramento de CPU, memória, disco e serviços
│   └── 04-servico-monitor.sh  # monitor como serviço + rotação de logs
├── api-teste/                 # API de teste (substituída pela API oficial)
├── evidencias/                # prints de execução
└── README.md
Scripts
Script	O que faz
01-infra.sh	Define o hostname passo-seguro, registra passo-seguro.local no /etc/hosts, ajusta o fuso para São Paulo, fixa o IP 192.168.56.10 na placa host-only, configura DNS (8.8.8.8 e 1.1.1.1), ativa o firewall deixando só SSH e HTTP abertos e testa internet, DNS e nome local.
02-app.sh	Instala o .NET SDK, o git e o Apache; cria o usuário de sistema passoseguro (sem login); baixa e compila a API; grava as variáveis de ambiente em /etc/passo-seguro/api.env; cria o serviço passo-seguro-api com reinício automático; configura o Apache para repassar a porta 80 para a API (com a permissão do SELinux) e testa as duas rotas.
03-monitor.sh	Mede o uso de CPU, memória e disco, verifica se a API e o Apache estão no ar e se a API responde em /health. Gera [ALERTA] quando um limite (80%) é ultrapassado ou um serviço cai. Roda uma vez (--uma-vez) ou em ciclo a cada 30 segundos.
04-servico-monitor.sh	Instala o monitor como serviço passo-seguro-monitor (liga com a VM e reinicia sozinho se cair) e configura a rotação diária dos logs, guardando 7 dias.

Todos os scripts:

só rodam como administrador (sudo);
registram cada ação com data, hora, nome do script e usuário que executou;
podem ser executados de novo sem duplicar configurações.
Como executar

Pré-requisitos na VM: AlmaLinux 10 com as duas placas de rede descritas acima, git instalado e acesso à internet.

bash
git clone https://github.com/Daniuss/passo-seguro-infra.git
cd passo-seguro-infra

sudo bash scripts/01-infra.sh            # infraestrutura
sudo bash scripts/02-app.sh              # aplicação
sudo bash scripts/04-servico-monitor.sh  # monitoramento como serviço

Depois, no navegador do Windows:

http://192.168.56.10/
http://192.168.56.10/health
http://192.168.56.10/api/ocorrencias
Aplicação hospedada

A COMPLETAR com a API oficial do grupo. No momento, o script 02-app.sh usa a API de teste da pasta api-teste/.

Item	Valor
Repositório da API	a completar
Tecnologia	C# / .NET (versão a completar)
Porta interna	5000
Rota de verificação	/health

Para trocar de API, basta alterar as variáveis no topo do scripts/02-app.sh (REPO_API, CAMINHO_CSPROJ, VERSAO_DOTNET, PORTA_API, ROTA_TESTE) e rodar o script de novo.

Monitoramento e alertas
Verificação	Alerta quando
Uso de CPU	≥ 80%
Uso de memória	≥ 80%
Uso do disco /	≥ 80%
Serviços passo-seguro-api e httpd	algum fora do ar
Rota /health da API	sem resposta em 5 segundos

Os limites e o intervalo ficam no topo do scripts/03-monitor.sh.

Comandos úteis:

bash
systemctl status passo-seguro-monitor          # estado do serviço
tail -f /var/log/passo-seguro/monitoramento.log # medições em tempo real
cat /var/log/passo-seguro/alertas.log           # só os alertas
Logs de auditoria
Arquivo	Conteúdo
/var/log/passo-seguro/provisionamento.log	Cada ação dos scripts 01, 02 e 04, com data, hora e usuário
/var/log/passo-seguro/monitoramento.log	Todas as medições do monitor
/var/log/passo-seguro/alertas.log	Somente os alertas
Journal do sistema (journalctl -t passo-seguro)	Cópia das ações e alertas
Journal dos serviços (journalctl -u passo-seguro-api)	Quedas e reinícios registrados pelo systemd

Rotação: /etc/logrotate.d/passo-seguro (diária, guarda 7 dias, compactados).

Teste de falha

1. Queda da API

bash
sudo kill -9 $(systemctl show -p MainPID --value passo-seguro-api)
sleep 6; systemctl show -p MainPID --value passo-seguro-api   # número novo = API religada
journalctl -u passo-seguro-api --no-pager -g KILL
journalctl -u passo-seguro-api --no-pager -g restart

Resultado: o systemd registra status=9/KILL e, 5 segundos depois, Scheduled restart job. A API volta sozinha.

2. Queda do monitor

bash
sudo kill -9 $(systemctl show -p MainPID --value passo-seguro-monitor)
sleep 6; systemctl show -p MainPID --value passo-seguro-monitor

Resultado: o monitor também é religado em 5 segundos.

3. CPU acima do limite

bash
yes > /dev/null &        # ocupa 100% de um núcleo
# aguardar cerca de 40 segundos
tail -5 /var/log/passo-seguro/alertas.log
pkill yes                # encerra a carga

Resultado: [ALERTA] CPU em 100% (limite 80%).

Evidências

Configuração da VM no VirtualBox (2 discos, NAT + host-only) VirtualBox

Estado inicial da VM (antes da expansão do disco e dos scripts) Estado inicial

Script 01 – infraestrutura Script 01

Script 03 – monitor com tudo normal Monitor OK

Script 03 – alertas com a API parada Alertas com a API parada

Script 03 – API religada, monitor volta ao normal Monitor recuperado

Teste de falha – monitor derrubado e religado pelo systemd Falha do monitor

Teste de falha – alerta de CPU em 100% Alerta de CPU

Vídeo de demonstração

Link a completar.
