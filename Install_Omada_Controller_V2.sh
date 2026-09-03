#!/usr/bin/env bash

###############################################################################
# =============================================================================
#                    CTIC-BTC IFMA CAMPUS BURITICUPU
#                    INSTALADOR OMADA CONTROLLER
# =============================================================================
#
# Nome        : Install_Omada_Controller.sh
# Versão      : 2.2
# Criador     : Adriano Freire
# Unidade     : CTIC-BTC - IFMA Campus Buriticupu
#
# Descrição:
#   Instalador modular e seguro do TP-Link Omada Software Controller.
#
# Fluxo:
#
#   01. Inicialização
#   02. Verificações do sistema
#   03. Escolha do MongoDB
#   04. Validação da escolha
#   05. Confirmação da instalação
#   06. Backup
#   07. Preparação do APT
#   08. Java 17+
#   09. JSVC
#   10. MongoDB
#   11. Omada Controller
#   12. Chromium (opcional)
#   13. Serviço Omada
#   14. Validação final
#   15. Relatório
#
# Princípios:
#
#   - Validar antes de alterar
#   - Não remover pacotes automaticamente
#   - Não executar apt-get -f install cegamente
#   - Backup antes das alterações
#   - Registrar todas as operações
#   - Permitir diagnóstico sem instalação
#   - Permitir pacote .deb local
#
###############################################################################

set -o pipefail

###############################################################################
# 01. IDENTIFICAÇÃO
###############################################################################

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="2.2"

OMADA_VERSION="6.2.14.11"

EXPECTED_ARCH="amd64"

###############################################################################
# 02. CONFIGURAÇÕES
###############################################################################

# ---------------------------------------------------------------------------
# Java
# ---------------------------------------------------------------------------

JAVA_MIN_VERSION="17"

# ---------------------------------------------------------------------------
# JSVC
# ---------------------------------------------------------------------------

JSVC_RECOMMENDED_VERSION="1.0.15"

# ---------------------------------------------------------------------------
# MongoDB
# ---------------------------------------------------------------------------

# Será definido durante a execução.
#
# Valores possíveis:
#
#   4.4
#   5
#   6
#   7
#   8
#

MONGODB_VERSION=""

# ---------------------------------------------------------------------------
# Chromium
# ---------------------------------------------------------------------------

INSTALL_CHROMIUM=false

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

CREATE_BACKUP=true

# ---------------------------------------------------------------------------
# Serviço
# ---------------------------------------------------------------------------

ENABLE_SERVICE=true
START_SERVICE=true

###############################################################################
# 03. DIRETÓRIOS
###############################################################################

BASE_DIR="/opt/omada-installer"

BACKUP_DIR="/opt/backups/omada"

LOG_DIR="/var/log/omada-installer"

TMP_DIR="/tmp/omada-installer"

LOG_FILE=""

###############################################################################
# 04. PARÂMETROS
###############################################################################

DEBUG=false
CHECK_ONLY=false
FORCE=false

LOCAL_DEB=""

###############################################################################
# 05. VARIÁVEIS DO SISTEMA
###############################################################################

OS_ID=""
OS_VERSION=""
OS_NAME=""
OS_CODENAME=""

ARCH=""

HOSTNAME_VALUE=""

SERVER_IP=""
DEFAULT_INTERFACE=""
DEFAULT_GATEWAY=""

CPU_MODEL=""
CPU_CORES=""

MEMORY_MB=""
DISK_MB=""

HAS_AVX=false

###############################################################################
# 06. VARIÁVEIS DAS DEPENDÊNCIAS
###############################################################################

JAVA_HOME=""
JAVA_VERSION=""

JSVC_VERSION=""

MONGODB_INSTALLED=false
MONGODB_INSTALLED_VERSION=""

###############################################################################
# 07. VARIÁVEIS DO OMADA
###############################################################################

PACKAGE_PATH=""
PACKAGE_VERSION=""
PACKAGE_ARCH=""

OMADA_INSTALLED=false
OMADA_INSTALLED_VERSION=""

OMADA_SERVICE=""

###############################################################################
# 08. CONTROLE DE FLUXO
###############################################################################

CURRENT_STEP="Inicialização"

###############################################################################
# 09. CORES
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

###############################################################################
# 10. LOG
###############################################################################

log() {

    echo -e "$*" | tee -a "$LOG_FILE"

}

info() {

    log "${BLUE}[INFO]${NC} $*"

}

ok() {

    log "${GREEN}[ OK ]${NC} $*"

}

warn() {

    log "${YELLOW}[AVISO]${NC} $*"

}

error() {

    log "${RED}[ERRO]${NC} $*"

}

section() {

    echo

    log "${CYAN}============================================================${NC}"
    log "${CYAN}$*${NC}"
    log "${CYAN}============================================================${NC}"

}

###############################################################################
# 11. ERRO FATAL
###############################################################################

fail() {

    error "$*"
    error "Etapa: $CURRENT_STEP"
    error "Instalação interrompida."
    error "Log: $LOG_FILE"

    exit 1

}

###############################################################################
# 12. LIMPEZA
###############################################################################

cleanup() {

    if [[ "$DEBUG" == true ]]; then

        info "Modo DEBUG ativo."
        info "Arquivos temporários preservados."

        return

    fi

    if [[ -d "$TMP_DIR" ]]; then

        rm -rf "$TMP_DIR"

    fi

}

trap cleanup EXIT

###############################################################################
# 13. AJUDA
###############################################################################

show_help() {

    cat <<EOF

CTIC-BTC IFMA CAMPUS BURITICUPU

Instalador Omada Controller ${SCRIPT_VERSION}

Uso:

    $SCRIPT_NAME [opções]

Opções:

    --check
        Executa somente as verificações.
        Nenhuma alteração será realizada.

    --debug
        Ativa modo de depuração.

    --force
        Permite operação forçada quando aplicável.

    --deb ARQUIVO
        Utiliza um pacote Omada .deb local.

    --mongodb VERSÃO
        Define a versão do MongoDB.

        Exemplos:
            --mongodb 8
            --mongodb 7
            --mongodb 6
            --mongodb 5
            --mongodb 4.4

    --chromium
        Instala Chromium.

    --no-backup
        Desativa o backup automático.

    --help
        Exibe esta ajuda.

Exemplos:

    $SCRIPT_NAME --check

    $SCRIPT_NAME

    $SCRIPT_NAME --mongodb 8

    $SCRIPT_NAME --deb /tmp/Omada.deb

    $SCRIPT_NAME --mongodb 7 --chromium

EOF

}

###############################################################################
# 14. ARGUMENTOS
###############################################################################

parse_arguments() {

    while [[ $# -gt 0 ]]; do

        case "$1" in

            --check)

                CHECK_ONLY=true
                shift
                ;;

            --debug)

                DEBUG=true
                shift
                ;;

            --force)

                FORCE=true
                shift
                ;;

            --chromium)

                INSTALL_CHROMIUM=true
                shift
                ;;

            --no-backup)

                CREATE_BACKUP=false
                shift
                ;;

            --mongodb)

                [[ -n "${2:-}" ]] \
                    || fail "Informe a versão do MongoDB."

                MONGODB_VERSION="$2"

                shift 2
                ;;

            --deb)

                [[ -n "${2:-}" ]] \
                    || fail "Informe o arquivo .deb."

                LOCAL_DEB="$2"

                shift 2
                ;;

            --help|-h)

                show_help
                exit 0
                ;;

            *)

                error "Opção desconhecida: $1"

                show_help

                exit 1
                ;;

        esac

    done

}

###############################################################################
# 15. AMBIENTE
###############################################################################

initialize_environment() {

    CURRENT_STEP="Inicialização do ambiente"

    mkdir -p "$BASE_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/installer"
    mkdir -p "$LOG_DIR"
    mkdir -p "$TMP_DIR"

    LOG_FILE="$LOG_DIR/install-$(date '+%Y%m%d-%H%M%S').log"

    touch "$LOG_FILE" \
        || fail "Não foi possível criar o arquivo de log."

    ok "Ambiente preparado."

    info "Log: $LOG_FILE"

}

###############################################################################
# 16. CABEÇALHO
###############################################################################

show_header() {

    clear 2>/dev/null || true

    echo
    echo "================================================================"
    echo "        CTIC-BTC IFMA CAMPUS BURITICUPU"
    echo "        INSTALADOR OMADA CONTROLLER"
    echo "================================================================"
    echo
    echo "        Instalador : ${SCRIPT_VERSION}"
    echo "        Omada      : ${OMADA_VERSION}"
    echo "        Criador    : Adriano Freire"
    echo
    echo "================================================================"
    echo

}

###############################################################################
# 17. ROOT
###############################################################################

check_root() {

    CURRENT_STEP="Verificação de privilégios"

    if [[ "$EUID" -ne 0 ]]; then

        fail "Execute este script como root."

    fi

    ok "Privilégios administrativos disponíveis."

}

###############################################################################
# 18. SISTEMA OPERACIONAL
###############################################################################

detect_os() {

    CURRENT_STEP="Detecção do sistema operacional"

    [[ -f /etc/os-release ]] \
        || fail "/etc/os-release não encontrado."

    source /etc/os-release

    OS_ID="$ID"
    OS_VERSION="$VERSION_ID"
    OS_NAME="$PRETTY_NAME"
    OS_CODENAME="${VERSION_CODENAME:-}"

    info "Sistema: $OS_NAME"
    info "Versão: $OS_VERSION"
    info "Codename: ${OS_CODENAME:-N/D}"

}

###############################################################################
# 19. COMPATIBILIDADE DO SO
###############################################################################

check_os_compatibility() {

    CURRENT_STEP="Compatibilidade do sistema operacional"

    case "$OS_ID" in

        debian)

            case "$OS_VERSION" in

                8|9|10|11|12)

                    ok "Debian $OS_VERSION reconhecido."

                    ;;

                *)

                    warn "Debian $OS_VERSION não está na lista validada."

                    ;;

            esac

            ;;

        ubuntu)

            case "$OS_VERSION" in

                16.04|18.04|20.04|22.04|24.04)

                    ok "Ubuntu $OS_VERSION reconhecido."

                    ;;

                *)

                    warn "Ubuntu $OS_VERSION não está na lista validada."

                    ;;

            esac

            ;;

        *)

            fail "Sistema operacional não suportado."

            ;;

    esac

}

###############################################################################
# 20. ARQUITETURA
###############################################################################

check_architecture() {

    CURRENT_STEP="Arquitetura"

    ARCH="$(dpkg --print-architecture)"

    info "Arquitetura: $ARCH"

    [[ "$ARCH" == "$EXPECTED_ARCH" ]] \
        || fail "Arquitetura incompatível."

    ok "Arquitetura amd64 confirmada."

}

###############################################################################
# 21. CPU
###############################################################################

check_cpu() {

    CURRENT_STEP="Processador"

    CPU_MODEL="$(
        awk -F: '/model name/ {
            print $2;
            exit
        }' /proc/cpuinfo \
        | sed 's/^ //'
    )"

    CPU_CORES="$(
        nproc
    )"

    info "CPU: ${CPU_MODEL:-N/D}"
    info "Núcleos: ${CPU_CORES:-N/D}"

    ok "CPU identificada."

}

###############################################################################
# 22. MEMÓRIA
###############################################################################

check_memory() {

    CURRENT_STEP="Memória"

    MEMORY_MB="$(
        awk '/MemTotal/ {
            printf "%.0f", $2/1024
        }' /proc/meminfo
    )"

    info "Memória: ${MEMORY_MB} MB"

    if (( MEMORY_MB < 2048 )); then

        warn "Memória inferior a 2 GB."

    else

        ok "Memória adequada."

    fi

}

###############################################################################
# 23. DISCO
###############################################################################

check_disk() {

    CURRENT_STEP="Armazenamento"

    DISK_MB="$(
        df -Pk / \
        | awk 'NR==2 {
            print int($4/1024)
        }'
    )"

    info "Espaço livre: ${DISK_MB} MB"

    if (( DISK_MB < 5000 )); then

        fail "Espaço em disco insuficiente."

    fi

    ok "Espaço em disco adequado."

}

###############################################################################
# 24. REDE
###############################################################################

get_network_info() {

    CURRENT_STEP="Informações de rede"

    DEFAULT_INTERFACE="$(
        ip route \
        | awk '/default/ {
            print $5;
            exit
        }'
    )"

    DEFAULT_GATEWAY="$(
        ip route \
        | awk '/default/ {
            print $3;
            exit
        }'
    )"

    SERVER_IP="$(
        hostname -I \
        | awk '{print $1}'
    )"

    HOSTNAME_VALUE="$(hostname)"

    info "Hostname: $HOSTNAME_VALUE"
    info "Interface: ${DEFAULT_INTERFACE:-N/D}"
    info "Gateway: ${DEFAULT_GATEWAY:-N/D}"
    info "IP: ${SERVER_IP:-N/D}"

}

###############################################################################
# 25. TESTE DE REDE
###############################################################################

check_network() {

    CURRENT_STEP="Conectividade de rede"

    if ip route | grep -q '^default'; then

        ok "Rota padrão encontrada."

    else

        warn "Rota padrão não encontrada."

    fi

    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then

        ok "Conectividade IP OK."

    else

        warn "Conectividade IP falhou."

    fi

    if getent hosts deb.debian.org >/dev/null 2>&1; then

        ok "Resolução DNS OK."

    else

        warn "Resolução DNS falhou."

    fi

}

###############################################################################
# 26. VERIFICAÇÃO AVX
#
# IMPORTANTE:
#
# AVX NÃO É REQUISITO GERAL DO OMADA.
#
# Esta função somente será executada caso seja escolhida uma versão
# do MongoDB que exija AVX.
#
###############################################################################

check_avx_for_mongodb() {

    CURRENT_STEP="Verificação AVX para MongoDB"

    case "$MONGODB_VERSION" in

        4|4.4)

            info "MongoDB ${MONGODB_VERSION} selecionado."
            info "AVX não é exigido para esta versão."

            HAS_AVX=false

            return 0

            ;;

        5|6|7|8)

            info "MongoDB ${MONGODB_VERSION} selecionado."
            info "Verificando suporte AVX..."

            if grep -qw avx /proc/cpuinfo; then

                HAS_AVX=true

                ok "CPU possui suporte AVX."

            else

                HAS_AVX=false

                error "CPU não possui suporte AVX."

                fail \
                "MongoDB ${MONGODB_VERSION} não pode ser utilizado nesta CPU."

            fi

            ;;

        *)

            fail "Versão MongoDB inválida."

            ;;

    esac

}

###############################################################################
# 27. SELEÇÃO DO MONGODB
###############################################################################

select_mongodb() {

    CURRENT_STEP="Seleção do MongoDB"

    # Se o usuário passou --mongodb,
    # não mostrar o menu.

    if [[ -n "$MONGODB_VERSION" ]]; then

        info "MongoDB definido por parâmetro:"
        info "$MONGODB_VERSION"

        return 0

    fi

    section "SELEÇÃO DO MONGODB"

    echo
    echo "Omada Controller: ${OMADA_VERSION}"
    echo
    echo "Escolha a versão do MongoDB:"
    echo
    echo "  [1] MongoDB 8"
    echo "  [2] MongoDB 7"
    echo "  [3] MongoDB 6"
    echo "  [4] MongoDB 5"
    echo "  [5] MongoDB 4.4"
    echo "  [0] Cancelar"
    echo

    while true; do

        read -rp "Digite sua opção [0-5]: " OPTION

        case "$OPTION" in

            1)
                MONGODB_VERSION="8"
                break
                ;;

            2)
                MONGODB_VERSION="7"
                break
                ;;

            3)
                MONGODB_VERSION="6"
                break
                ;;

            4)
                MONGODB_VERSION="5"
                break
                ;;

            5)
                MONGODB_VERSION="4.4"
                break
                ;;

            0)

                info "Operação cancelada."

                exit 0

                ;;

            *)

                warn "Opção inválida."

                ;;

        esac

    done

    ok "MongoDB selecionado: ${MONGODB_VERSION}"

}

###############################################################################
# 28. VALIDAÇÃO DA ESCOLHA
###############################################################################

validate_mongodb_selection() {

    CURRENT_STEP="Validação da versão MongoDB"

    case "$MONGODB_VERSION" in

        4|4.4|5|6|7|8)

            ok "Versão MongoDB válida."

            ;;

        *)

            fail "Versão MongoDB inválida: $MONGODB_VERSION"

            ;;

    esac

}

###############################################################################
# 29. CONFIRMAÇÃO
###############################################################################

confirm_installation() {

    CURRENT_STEP="Confirmação da instalação"

    section "RESUMO DA INSTALAÇÃO"

    echo
    echo "Sistema       : $OS_NAME"
    echo "Arquitetura   : $ARCH"
    echo "Hostname      : $HOSTNAME_VALUE"
    echo "IP            : $SERVER_IP"
    echo
    echo "Omada         : $OMADA_VERSION"
    echo "MongoDB       : $MONGODB_VERSION"
    echo "Java mínimo   : $JAVA_MIN_VERSION"
    echo "JSVC          : $JSVC_RECOMMENDED_VERSION"
    echo
    echo "Backup        : $CREATE_BACKUP"
    echo "Chromium      : $INSTALL_CHROMIUM"
    echo

    read -rp \
        "Deseja prosseguir com a instalação? [s/N]: " CONFIRM

    case "$CONFIRM" in

        s|S|sim|SIM|Sim)

            ok "Instalação confirmada."

            ;;

        *)

            info "Instalação cancelada pelo administrador."

            exit 0

            ;;

    esac

}

###############################################################################
# 30. BACKUP
###############################################################################

create_backup() {

    CURRENT_STEP="Backup"

    if [[ "$CREATE_BACKUP" != true ]]; then

        warn "Backup automático desativado."

        return 0

    fi

    local timestamp
    local backup_dir

    timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"

    backup_dir="$BACKUP_DIR/installer/$timestamp"

    mkdir -p "$backup_dir"

    info "Criando backup..."

    # -----------------------------------------------------------------------
    # Informações do sistema
    # -----------------------------------------------------------------------

    dpkg -l > "$backup_dir/dpkg-list.txt"

    cp /etc/hosts \
        "$backup_dir/hosts" \
        2>/dev/null || true

    cp /etc/hostname \
        "$backup_dir/hostname" \
        2>/dev/null || true

    # -----------------------------------------------------------------------
    # Instalação anterior do Omada
    # -----------------------------------------------------------------------

    if [[ -d /opt/tplink ]]; then

        info "Encontrado /opt/tplink."

        tar -czf \
            "$backup_dir/omada-files.tar.gz" \
            /opt/tplink \
            2>/dev/null \
            || warn "Falha no backup de /opt/tplink."

    fi

    # -----------------------------------------------------------------------
    # MongoDB
    # -----------------------------------------------------------------------

    if command -v mongodump >/dev/null 2>&1; then

        mkdir -p "$backup_dir/mongodb"

        if mongodump \
            --out "$backup_dir/mongodb" \
            >> "$LOG_FILE" 2>&1; then

            ok "Backup do MongoDB realizado."

        else

            warn "mongodump falhou."

        fi

    else

        warn "mongodump não disponível."

    fi

    ok "Backup concluído."

    info "Local:"
    info "$backup_dir"

}

###############################################################################
# 31. APT
###############################################################################

prepare_apt() {

    CURRENT_STEP="Preparação do APT"

    info "Atualizando índices do APT..."

    apt-get update \
        || fail "apt-get update falhou."

    ok "APT atualizado."

}

###############################################################################
# 32. DEPENDÊNCIAS BÁSICAS
###############################################################################

install_base_dependencies() {

    CURRENT_STEP="Dependências básicas"

    apt-get install -y \
        curl \
        wget \
        gnupg \
        ca-certificates \
        lsb-release \
        file \
        tar \
        gzip \
        procps \
        iproute2 \
        net-tools \
        || fail "Falha nas dependências básicas."

    ok "Dependências básicas instaladas."

}

###############################################################################
# 33. JAVA
###############################################################################

check_java() {

    CURRENT_STEP="Java"

    if ! command -v java >/dev/null 2>&1; then

        return 1

    fi

    JAVA_VERSION="$(
        java -version 2>&1 \
        | awk -F '"' '/version/ {
            print $2;
            exit
        }'
    )"

    info "Java detectado: ${JAVA_VERSION:-N/D}"

    return 0

}

###############################################################################
# 34. INSTALAÇÃO JAVA
###############################################################################

install_java() {

    CURRENT_STEP="Instalação Java"

    if check_java; then

        ok "Java já instalado."

    else

        info "Instalando OpenJDK 17..."

        apt-get install -y \
            openjdk-17-jre-headless \
            || fail "Falha na instalação do Java."

    fi

    check_java \
        || fail "Java não está disponível."

}

###############################################################################
# 35. JAVA_HOME
###############################################################################

configure_java_home() {

    CURRENT_STEP="Configuração JAVA_HOME"

    local java_bin

    java_bin="$(
        readlink -f "$(command -v java)"
    )"

    JAVA_HOME="$(
        dirname "$(dirname "$java_bin")"
    )"

    export JAVA_HOME

    info "JAVA_HOME=$JAVA_HOME"

    [[ -x "$JAVA_HOME/bin/java" ]] \
        || fail "JAVA_HOME inválido."

    ok "JAVA_HOME validado."

}

###############################################################################
# 36. JSVC
###############################################################################

check_jsvc() {

    CURRENT_STEP="JSVC"

    if ! command -v jsvc >/dev/null 2>&1; then

        warn "JSVC não encontrado."

        return 1

    fi

    JSVC_VERSION="$(
        jsvc -version 2>&1 \
        | head -n 1
    )"

    info "JSVC: ${JSVC_VERSION:-N/D}"

    return 0

}

###############################################################################
# 37. INSTALAÇÃO JSVC
###############################################################################

install_jsvc() {

    CURRENT_STEP="Instalação JSVC"

    if check_jsvc; then

        ok "JSVC disponível."

        return 0

    fi

    info "Instalando JSVC..."

    apt-get install -y jsvc \
        || fail "Falha ao instalar JSVC."

    check_jsvc \
        || fail "JSVC não disponível."

    ok "JSVC instalado."

}

###############################################################################
# 38. MONGODB — REPOSITÓRIO
###############################################################################

configure_mongodb_repository() {

    CURRENT_STEP="Repositório MongoDB"

    # IMPLEMENTAR:
    #
    # Aqui será feita a configuração do repositório oficial MongoDB
    # de acordo com:
    #
    #   OS_ID
    #   OS_VERSION
    #   OS_CODENAME
    #   MONGODB_VERSION
    #
    # Não utilizar apt-key.
    #
    # Utilizar:
    #
    # /usr/share/keyrings/
    #
    # e:
    #
    # /etc/apt/sources.list.d/
    #

    info "Preparando repositório MongoDB ${MONGODB_VERSION}."

}

###############################################################################
# 39. MONGODB — DETECÇÃO
###############################################################################

check_mongodb() {

    CURRENT_STEP="Detecção MongoDB"

    if ! command -v mongod >/dev/null 2>&1; then

        MONGODB_INSTALLED=false

        warn "MongoDB não encontrado."

        return 1

    fi

    MONGODB_INSTALLED=true

    MONGODB_INSTALLED_VERSION="$(
        mongod --version \
        | awk '/db version/ {
            print $3;
            exit
        }'
    )"

    info "MongoDB instalado:"
    info "$MONGODB_INSTALLED_VERSION"

    return 0

}

###############################################################################
# 40. MONGODB — INSTALAÇÃO
###############################################################################

install_mongodb() {

    CURRENT_STEP="Instalação MongoDB"

    if check_mongodb; then

        warn "MongoDB já está instalado."

        return 0

    fi

    configure_mongodb_repository

    apt-get update \
        || fail "Falha ao atualizar APT após configurar MongoDB."

    # IMPLEMENTAR:
    #
    # Instalação da versão selecionada.
    #
    # Exemplo:
    #
    # apt-get install mongodb-org
    #
    # A seleção da versão deverá ser respeitada.

    info "Instalando MongoDB ${MONGODB_VERSION}."

}

###############################################################################
# 41. MONGODB — SERVIÇO
###############################################################################

start_mongodb() {

    CURRENT_STEP="Serviço MongoDB"

    if ! command -v mongod >/dev/null 2>&1; then

        fail "mongod não encontrado."

    fi

    systemctl enable mongod \
        || warn "Não foi possível habilitar mongod."

    systemctl start mongod \
        || fail "Não foi possível iniciar MongoDB."

    sleep 3

    if systemctl is-active --quiet mongod; then

        ok "MongoDB está ativo."

    else

        systemctl status mongod --no-pager \
            | tee -a "$LOG_FILE"

        fail "MongoDB não iniciou."

    fi

}

###############################################################################
# 42. MONGODB — VALIDAÇÃO
###############################################################################

validate_mongodb() {

    CURRENT_STEP="Validação MongoDB"

    check_mongodb \
        || fail "MongoDB não está instalado."

    if ! systemctl is-active --quiet mongod; then

        fail "MongoDB não está ativo."

    fi

    ok "MongoDB validado."

}

###############################################################################
# 43. OMADA — DETECÇÃO
###############################################################################

check_existing_omada() {

    CURRENT_STEP="Detecção do Omada"

    if dpkg-query -W -f='${Status}' omadac 2>/dev/null \
        | grep -q "install ok installed"; then

        OMADA_INSTALLED=true

        OMADA_INSTALLED_VERSION="$(
            dpkg-query -W -f='${Version}' omadac
        )"

        ok "Omada instalado:"
        info "$OMADA_INSTALLED_VERSION"

    else

        OMADA_INSTALLED=false

        info "Omada não está instalado."

    fi

}

###############################################################################
# 44. OMADA — URL
###############################################################################

OMADA_URL="https://static.tp-link.com/upload/software/2026/202607/20260717/Omada_SDN_Controller_v6.2.14.11_linux_x64.deb"

###############################################################################
# 45. OMADA — DOWNLOAD
###############################################################################

download_omada() {

    CURRENT_STEP="Download Omada"

    mkdir -p "$TMP_DIR"

    if [[ -n "$LOCAL_DEB" ]]; then

        [[ -f "$LOCAL_DEB" ]] \
            || fail "Arquivo .deb local não encontrado."

        PACKAGE_PATH="$LOCAL_DEB"

        ok "Utilizando pacote local."

        return 0

    fi

    PACKAGE_PATH="$TMP_DIR/$(basename "$OMADA_URL")"

    info "Baixando Omada Controller..."

    info "$OMADA_URL"

    curl -fL \
        --connect-timeout 15 \
        --max-time 1800 \
        -o "$PACKAGE_PATH" \
        "$OMADA_URL" \
        || fail "Falha no download do Omada."

    ok "Download concluído."

}

###############################################################################
# 46. OMADA — VALIDAÇÃO
###############################################################################

validate_omada_package() {

    CURRENT_STEP="Validação pacote Omada"

    [[ -f "$PACKAGE_PATH" ]] \
        || fail "Pacote Omada não encontrado."

    if ! dpkg-deb --info "$PACKAGE_PATH" >/dev/null 2>&1; then

        fail "Pacote .deb inválido ou corrompido."

    fi

    PACKAGE_VERSION="$(
        dpkg-deb -W -f "$PACKAGE_PATH" Version
    )"

    PACKAGE_ARCH="$(
        dpkg-deb -W -f "$PACKAGE_PATH" Architecture
    )"

    info "Versão do pacote: $PACKAGE_VERSION"
    info "Arquitetura: $PACKAGE_ARCH"

    if [[ "$PACKAGE_ARCH" != "all" &&
          "$PACKAGE_ARCH" != "$EXPECTED_ARCH" ]]; then

        fail "Arquitetura do pacote incompatível."

    fi

    ok "Pacote Omada validado."

}

###############################################################################
# 47. OMADA — MÉTODO DE INSTALAÇÃO
###############################################################################

determine_omada_install_method() {

    CURRENT_STEP="Método de instalação Omada"

    # IMPLEMENTAR:
    #
    # Determinar:
    #
    # Java >= 11
    # JSVC >= 1.1.0
    #
    # Caso:
    #
    # dpkg --ignore-depends=jsvc
    #
    # conforme documentação oficial.
    #
    # Caso contrário:
    #
    # dpkg -i
    #

    OMADA_IGNORE_JSVC=false

    ok "Método de instalação definido."

}

###############################################################################
# 48. OMADA — INSTALAÇÃO
###############################################################################

install_omada() {

    CURRENT_STEP="Instalação Omada"

    determine_omada_install_method

    info "Instalando Omada Controller."

    if [[ "$OMADA_IGNORE_JSVC" == true ]]; then

        dpkg \
            --ignore-depends=jsvc \
            -i "$PACKAGE_PATH"

    else

        dpkg \
            -i "$PACKAGE_PATH"

    fi

    local result=$?

    if (( result != 0 )); then

        error "dpkg retornou código $result."

        error "O pacote NÃO será removido automaticamente."

        error "Não será executado apt-get -f install."

        dpkg -l \
            | grep -Ei \
                'omadac|mongodb|jsvc|openjdk' \
            | tee -a "$LOG_FILE" \
            || true

        fail "Falha na instalação do Omada."

    fi

    ok "Omada instalado."

}

###############################################################################
# 49. OMADA — DEPENDÊNCIAS
###############################################################################

validate_omada_dependencies() {

    CURRENT_STEP="Dependências Omada"

    if dpkg-query -W -f='${Status}' omadac 2>/dev/null \
        | grep -q "install ok installed"; then

        ok "Pacote Omada configurado."

    else

        fail "Pacote Omada não está configurado corretamente."

    fi

}

###############################################################################
# 50. CHROMIUM
###############################################################################

install_chromium() {

    CURRENT_STEP="Chromium"

    if [[ "$INSTALL_CHROMIUM" != true ]]; then

        info "Chromium não solicitado."

        return 0

    fi

    info "Instalando Chromium..."

    # IMPLEMENTAR
    #
    # Validar versão suportada pela versão do Controller.
    #

    apt-get install -y chromium \
        || fail "Falha na instalação do Chromium."

    ok "Chromium instalado."

}

###############################################################################
# 51. SERVIÇO OMADA
###############################################################################

detect_omada_service() {

    CURRENT_STEP="Detecção serviço Omada"

    if systemctl list-unit-files \
        | grep -q '^omadac.service'; then

        OMADA_SERVICE="omadac"

        ok "Serviço omadac encontrado."

        return 0

    fi

    if systemctl list-unit-files \
        | grep -q '^tpeap.service'; then

        OMADA_SERVICE="tpeap"

        ok "Serviço tpeap encontrado."

        return 0

    fi

    warn "Serviço Omada não identificado."

    return 1

}

###############################################################################
# 52. CONFIGURAR SERVIÇO
###############################################################################

configure_omada_service() {

    CURRENT_STEP="Configuração serviço Omada"

    systemctl daemon-reload

    detect_omada_service \
        || fail "Serviço Omada não encontrado."

    if [[ "$ENABLE_SERVICE" == true ]]; then

        systemctl enable "$OMADA_SERVICE" \
            || fail "Não foi possível habilitar o serviço."

        ok "Serviço habilitado."

    fi

}

###############################################################################
# 53. INICIAR OMADA
###############################################################################

start_omada() {

    CURRENT_STEP="Inicialização Omada"

    if [[ "$START_SERVICE" != true ]]; then

        info "Inicialização automática desativada."

        return 0

    fi

    systemctl start "$OMADA_SERVICE" \
        || fail "Não foi possível iniciar Omada."

    sleep 5

    if systemctl is-active --quiet "$OMADA_SERVICE"; then

        ok "Omada está ativo."

    else

        systemctl status "$OMADA_SERVICE" \
            --no-pager \
            | tee -a "$LOG_FILE"

        fail "Omada não iniciou."

    fi

}

###############################################################################
# 54. PORTAS
###############################################################################

check_ports() {

    CURRENT_STEP="Verificação das portas"

    info "Portas em escuta:"

    ss -lntup \
        | tee -a "$LOG_FILE"

    ok "Verificação de portas concluída."

}

###############################################################################
# 55. TESTE FINAL
###############################################################################

test_omada_service() {

    CURRENT_STEP="Teste final Omada"

    if [[ -z "$OMADA_SERVICE" ]]; then

        fail "Serviço Omada não identificado."

    fi

    if systemctl is-active --quiet "$OMADA_SERVICE"; then

        ok "Serviço Omada ativo."

    else

        fail "Serviço Omada está parado."

    fi

}

###############################################################################
# 56. DIAGNÓSTICO
###############################################################################

diagnostic_summary() {

    section "DIAGNÓSTICO FINAL"

    echo
    echo "Sistema operacional : ${OS_NAME:-N/D}"
    echo "Versão SO           : ${OS_VERSION:-N/D}"
    echo "Arquitetura         : ${ARCH:-N/D}"
    echo "Hostname            : ${HOSTNAME_VALUE:-N/D}"
    echo "IP                  : ${SERVER_IP:-N/D}"
    echo
    echo "CPU                 : ${CPU_MODEL:-N/D}"
    echo "Núcleos             : ${CPU_CORES:-N/D}"
    echo "Memória             : ${MEMORY_MB:-N/D} MB"
    echo "Disco livre         : ${DISK_MB:-N/D} MB"
    echo
    echo "Java                : ${JAVA_VERSION:-N/D}"
    echo "JAVA_HOME           : ${JAVA_HOME:-N/D}"
    echo "JSVC                : ${JSVC_VERSION:-N/D}"
    echo
    echo "MongoDB escolhido   : ${MONGODB_VERSION:-N/D}"
    echo "MongoDB instalado   : ${MONGODB_INSTALLED_VERSION:-N/D}"
    echo "AVX                 : ${HAS_AVX}"
    echo
    echo "Omada               : ${PACKAGE_VERSION:-N/D}"
    echo "Serviço             : ${OMADA_SERVICE:-N/D}"
    echo
    echo "Log                 : ${LOG_FILE:-N/D}"
    echo

}

###############################################################################
# 57. MODO CHECK
###############################################################################

run_check_mode() {

    section "MODO DIAGNÓSTICO"

    check_root

    detect_os

    check_os_compatibility

    check_architecture

    check_cpu

    check_memory

    check_disk

    get_network_info

    check_network

    echo

    info "Java:"
    check_java || warn "Java não instalado."

    echo

    info "JSVC:"
    check_jsvc || warn "JSVC não instalado."

    echo

    info "MongoDB:"
    check_mongodb || warn "MongoDB não instalado."

    echo

    info "Omada:"
    check_existing_omada

    echo

    diagnostic_summary

    ok "Diagnóstico concluído."

    exit 0

}

###############################################################################
# 58. FLUXO PRINCIPAL
###############################################################################

main() {

    parse_arguments "$@"

    initialize_environment

    show_header

    ###########################################################################
    # 01 — VERIFICAÇÕES INICIAIS
    ###########################################################################

    section "01 — VERIFICAÇÕES INICIAIS"

    check_root

    detect_os

    check_os_compatibility

    check_architecture

    check_cpu

    check_memory

    check_disk

    get_network_info

    check_network

    ###########################################################################
    # MODO CHECK
    ###########################################################################

    if [[ "$CHECK_ONLY" == true ]]; then

        run_check_mode

    fi

    ###########################################################################
    # 02 — SELEÇÃO MONGODB
    ###########################################################################

    section "02 — SELEÇÃO DO MONGODB"

    select_mongodb

    validate_mongodb_selection

    ###########################################################################
    # 03 — AVX CONDICIONAL
    ###########################################################################

    section "03 — VALIDAÇÃO DO MONGODB"

    check_avx_for_mongodb

    ###########################################################################
    # 04 — CONFIRMAÇÃO
    ###########################################################################

    section "04 — CONFIRMAÇÃO"

    confirm_installation

    ###########################################################################
    # 05 — BACKUP
    ###########################################################################

    section "05 — BACKUP"

    create_backup

    ###########################################################################
    # 06 — PREPARAÇÃO
    ###########################################################################

    section "06 — PREPARAÇÃO DO SISTEMA"

    prepare_apt

    install_base_dependencies

    ###########################################################################
    # 07 — JAVA
    ###########################################################################

    section "07 — JAVA"

    install_java

    configure_java_home

    ###########################################################################
    # 08 — JSVC
    ###########################################################################

    section "08 — JSVC"

    install_jsvc

    ###########################################################################
    # 09 — MONGODB
    ###########################################################################

    section "09 — MONGODB"

    install_mongodb

    start_mongodb

    validate_mongodb

    ###########################################################################
    # 10 — OMADA
    ###########################################################################

    section "10 — OMADA CONTROLLER"

    check_existing_omada

    if [[ "$OMADA_INSTALLED" == true &&
          "$FORCE" != true ]]; then

        warn "Omada já está instalado."

        info "Versão: $OMADA_INSTALLED_VERSION"

        info "Use --force para continuar."

        diagnostic_summary

        exit 0

    fi

    download_omada

    validate_omada_package

    install_omada

    validate_omada_dependencies

    ###########################################################################
    # 11 — CHROMIUM
    ###########################################################################

    section "11 — CHROMIUM"

    install_chromium

    ###########################################################################
    # 12 — SERVIÇO
    ###########################################################################

    section "12 — SERVIÇO OMADA"

    configure_omada_service

    start_omada

    ###########################################################################
    # 13 — VALIDAÇÃO
    ###########################################################################

    section "13 — VALIDAÇÃO FINAL"

    check_ports

    test_omada_service

    ###########################################################################
    # 14 — RESULTADO
    ###########################################################################

    section "14 — RESULTADO"

    diagnostic_summary

    success_summary

}

###############################################################################
# 59. SUCESSO
###############################################################################

success_summary() {

    section "INSTALAÇÃO CONCLUÍDA"

    echo
    echo "Omada Controller instalado com sucesso."
    echo
    echo "Versão Omada : ${PACKAGE_VERSION:-$OMADA_VERSION}"
    echo "MongoDB      : ${MONGODB_INSTALLED_VERSION:-$MONGODB_VERSION}"
    echo "Servidor     : ${SERVER_IP:-N/D}"
    echo "Hostname     : ${HOSTNAME_VALUE:-N/D}"
    echo
    echo "Acesse o Controller pelo navegador."
    echo
    echo "Log:"
    echo "$LOG_FILE"
    echo

}

###############################################################################
# 60. EXECUÇÃO
###############################################################################

main "$@"

###############################################################################
# FIM
###############################################################################
