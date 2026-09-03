#!/usr/bin/env bash

###############################################################################
# =============================================================================
#                         CTIC-BTC - IFMA
#                   CAMPUS BURITICUPU - MA
# =============================================================================
#
#                  OMADA SDN CONTROLLER - 2.1
#
#  Descrição:
#    Ferramenta de instalação, manutenção, backup, restauração,
#    remoção e diagnóstico do TP-Link Omada SDN Controller.
#
#  Sistemas suportados:
#    - Debian 11
#    - Debian 12
#    - Debian 13
#    - Ubuntu 20.04
#    - Ubuntu 22.04
#    - Ubuntu 24.04
#
#  Arquitetura:
#    - amd64
#
#  Java:
#    - OpenJDK 17
#
#  Criador:
#    Adriano Freire
#    CTIC-BTC - IFMA Campus Buriticupu
#
#  Versão:
#    2.1
#
#  Data:
#    2026
#
# =============================================================================
###############################################################################

set -Eeuo pipefail

###############################################################################
# CONFIGURAÇÕES
###############################################################################

SCRIPT_NAME="Omada Controller Installer"
SCRIPT_VERSION="2.1"

LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/omada-installer.log"

BACKUP_BASE="/opt/backups/omada"
INSTALLER_BACKUP_DIR="${BACKUP_BASE}/installer"

TMP_DIR="/tmp/omada-installer"

OMADA_PACKAGE=""
OMADA_VERSION=""
OMADA_URL=""

OS_ID=""
OS_VERSION=""
OS_NAME=""
ARCH=""

JAVA_VERSION=""

DRY_RUN=false

###############################################################################
# CORES
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

###############################################################################
# LOG
###############################################################################

initialize_log() {

    mkdir -p "${LOG_DIR}"

    touch "${LOG_FILE}"

    chmod 600 "${LOG_FILE}"

    {
        echo
        echo "============================================================"
        echo "Omada Controller Installer ${SCRIPT_VERSION}"
        echo "Data: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Usuário: $(id -un)"
        echo "Hostname: $(hostname)"
        echo "============================================================"
    } >> "${LOG_FILE}"
}

log() {

    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"

}

success() {

    echo -e "${GREEN}[ OK ]${NC} $*" | tee -a "${LOG_FILE}"

}

warning() {

    echo -e "${YELLOW}[AVISO]${NC} $*" | tee -a "${LOG_FILE}"

}

error() {

    echo -e "${RED}[ERRO]${NC} $*" | tee -a "${LOG_FILE}" >&2

}

die() {

    error "$*"

    exit 1

}

###############################################################################
# TRATAMENTO DE ERROS
###############################################################################

trap 'error "Falha na linha ${LINENO}: ${BASH_COMMAND}"' ERR

###############################################################################
# LIMPEZA TEMPORÁRIA
###############################################################################

cleanup() {

    if [[ -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
    fi

}

trap cleanup EXIT

###############################################################################
# CABEÇALHO
###############################################################################

show_header() {

    clear 2>/dev/null || true

    echo -e "${CYAN}"

    cat <<'EOF'

 ██████╗████████╗██╗ ██████╗       ██████╗ ████████╗ ██████╗
██╔════╝╚══██╔══╝██║██╔════╝      ██╔═══██╗╚══██╔══╝██╔════╝
██║        ██║   ██║██║     █████╗██║ ██║     ██║   ██║
██║        ██║   ██║██║     ╚════╝██║   ██║   ██║   ██║
╚██████╗   ██║   ██║╚██████╗      ╚██████╔╝   ██║   ╚██████╗
 ╚═════╝   ╚═╝   ╚═╝ ╚═════╝       ╚═════╝    ╚═╝    ╚═════╝

EOF

    echo -e "${WHITE}"
    echo "        INSTITUTO FEDERAL DO MARANHÃO - IFMA"
    echo "             CAMPUS BURITICUPU - BTC"
    echo
    echo "             COORDENADORIA DE TIC"
    echo
    echo -e "${GREEN}        OMADA SDN CONTROLLER - 2.1${NC}"
    echo
    echo "                 Criador:"
    echo "               Adriano Freire"
    echo
    echo "=========================================================================="
    echo -e "${NC}"

}

###############################################################################
# ROOT
###############################################################################

check_root() {

    if [[ "${EUID}" -ne 0 ]]; then

        die "Este script precisa ser executado como root.

Utilize:

    sudo bash $0"

    fi

}

###############################################################################
# SISTEMA OPERACIONAL
###############################################################################

detect_os() {

    [[ -f /etc/os-release ]] || \
        die "Arquivo /etc/os-release não encontrado."

    source /etc/os-release

    OS_ID="${ID}"
    OS_VERSION="${VERSION_ID}"
    OS_NAME="${PRETTY_NAME}"

    log "Sistema operacional: ${OS_NAME}"

    case "${OS_ID}" in

        debian)

            case "${OS_VERSION}" in

                11|12|13)
                    success "Debian ${OS_VERSION} suportado."
                    ;;

                *)
                    die "Debian ${OS_VERSION} não suportado."
                    ;;

            esac
            ;;

        ubuntu)

            case "${OS_VERSION}" in

                20.04|22.04|24.04)
                    success "Ubuntu ${OS_VERSION} suportado."
                    ;;

                *)
                    die "Ubuntu ${OS_VERSION} não suportado."
                    ;;

            esac
            ;;

        *)

            die "Sistema operacional não suportado: ${OS_ID}"

            ;;

    esac

}

###############################################################################
# ARQUITETURA
###############################################################################

check_architecture() {

    ARCH="$(dpkg --print-architecture)"

    log "Arquitetura: ${ARCH}"

    if [[ "${ARCH}" != "amd64" ]]; then

        die "Arquitetura ${ARCH} não suportada.

O instalador atualmente trabalha com amd64."

    fi

}

###############################################################################
# INTERNET
###############################################################################

check_internet() {

    log "Verificando conectividade de rede..."

    # Verifica rota padrão
    if ! ip route | grep -q '^default'; then
        die "Nenhuma rota padrão foi encontrada."
    fi

    success "Rota padrão encontrada."

    # Verifica conectividade IP
    if ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
        success "Conectividade IP OK."
    else
        die "Não foi possível alcançar a Internet por IP."
    fi

    # Verifica DNS
    if getent hosts deb.debian.org >/dev/null 2>&1; then
        success "Resolução DNS OK."
    else
        die "Falha na resolução DNS."
    fi

    # Verifica HTTPS
    if curl \
        -fsSL \
        --connect-timeout 10 \
        --max-time 20 \
        https://deb.debian.org/ \
        >/dev/null 2>&1; then

        success "Conectividade HTTPS OK."

    else

        warning "HTTPS para deb.debian.org falhou."

    fi

    # Teste separado da TP-Link
    if curl \
        -fsSL \
        --connect-timeout 10 \
        --max-time 20 \
        https://www.tp-link.com/ \
        >/dev/null 2>&1; then

        success "Acesso à TP-Link OK."

    else

        warning "Não foi possível acessar diretamente a TP-Link."
        warning "Isso não significa necessariamente que o servidor esteja sem Internet."

    fi
}

###############################################################################
# DEPENDÊNCIAS
###############################################################################

install_dependencies() {

    log "Atualizando repositórios..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update

    log "Instalando dependências..."

    apt-get install -y \
        ca-certificates \
        curl \
        wget \
        gnupg \
        jsvc \
        openjdk-17-jre-headless \
        lsb-release \
        procps \
        iproute2

    success "Dependências instaladas."

}

###############################################################################
# JAVA
###############################################################################

check_java() {

    command -v java >/dev/null 2>&1 || \
        die "Java não encontrado."

    JAVA_VERSION="$(java -version 2>&1 | head -n 1)"

    log "Java detectado: ${JAVA_VERSION}"

    if ! java -version 2>&1 | grep -qE '"17([.]|")'; then

        die "O Omada Controller 6.x requer Java 17.

Versão encontrada:
${JAVA_VERSION}"

    fi

    success "OpenJDK 17 validado."

}

###############################################################################
# DETECTAR OMADA
###############################################################################

detect_omada() {

    log "Verificando instalação existente do Omada..."

    if dpkg-query -W -f='${Status}' omadac 2>/dev/null \
        | grep -q "install ok installed"; then

        OMADA_VERSION="$(dpkg-query \
            -W \
            -f='${Version}' \
            omadac 2>/dev/null || true)"

        success "Omada instalado: ${OMADA_VERSION}"

        return 0

    fi

    if dpkg-query -W -f='${Status}' omadac 2>/dev/null \
        | grep -q "reinstreq"; then

        warning "Pacote omadac está em estado inconsistente."

        dpkg-query \
            -W \
            -f='Status: ${Status}\nVersion: ${Version}\n' \
            omadac \
            2>/dev/null || true

        return 0

    fi

    log "Nenhuma instalação funcional do Omada detectada."

}

###############################################################################
# DIRETÓRIOS OMADA
###############################################################################

find_omada_directories() {

    echo
    log "Procurando diretórios relacionados ao Omada..."

    local results

    results="$(
        find /opt /etc /var/lib /var/log /usr/local \
            -maxdepth 4 \
            -type d \
            \( \
                -iname '*omada*' \
                -o \
                -iname '*tplink*' \
                -o \
                -iname '*eapcontroller*' \
            \) \
            2>/dev/null \
            | sort
    )"

    if [[ -n "${results}" ]]; then

        echo "${results}"

    else

        log "Nenhum diretório Omada encontrado."

    fi

}

###############################################################################
# MONGODB
###############################################################################

check_mongodb() {

    echo
    log "Verificando MongoDB..."

    if command -v mongod >/dev/null 2>&1; then

        success "mongod encontrado."

        mongod --version 2>/dev/null \
            | head -n 2 \
            | tee -a "${LOG_FILE}" || true

    else

        warning "mongod não encontrado."

    fi

    if command -v mongodump >/dev/null 2>&1; then

        success "mongodump encontrado."

    else

        warning "mongodump não encontrado."

    fi

    if command -v mongorestore >/dev/null 2>&1; then

        success "mongorestore encontrado."

    else

        warning "mongorestore não encontrado."

    fi

}

###############################################################################
# SERVIÇO MONGODB
###############################################################################

mongodb_status() {

    echo
    echo "Status MongoDB:"
    echo

    systemctl status mongod \
        --no-pager \
        --full \
        2>/dev/null || true

}

###############################################################################
# BACKUP
###############################################################################

create_backup() {

    local timestamp
    local current_backup

    timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"

    current_backup="${INSTALLER_BACKUP_DIR}/${timestamp}"

    mkdir -p "${current_backup}"

    log "Criando backup:"
    log "${current_backup}"

    ###########################################################################
    # Informações do sistema
    ###########################################################################

    {
        echo "Data: $(date)"
        echo "Hostname: $(hostname)"
        echo "Sistema: ${OS_NAME:-desconhecido}"
        echo "Kernel: $(uname -a)"
        echo "Arquitetura: ${ARCH:-desconhecida}"
    } > "${current_backup}/system-info.txt"

    ###########################################################################
    # Pacote Omada
    ###########################################################################

    dpkg-query \
        -W \
        -f='${Package} ${Version} ${Status}\n' \
        omadac \
        > "${current_backup}/omadac-package.txt" \
        2>/dev/null || true

    ###########################################################################
    # Diretórios Omada
    ###########################################################################

    for dir in \
        /opt/tplink \
        /opt/omada \
        /etc/omada
    do

        if [[ -d "${dir}" ]]; then

            log "Copiando ${dir}..."

            mkdir -p "${current_backup}/files"

            cp -a \
                "${dir}" \
                "${current_backup}/files/"

        fi

    done

    ###########################################################################
    # Configurações dpkg
    ###########################################################################

    if [[ -f /var/lib/dpkg/info/omadac.list ]]; then

        cp -a \
            /var/lib/dpkg/info/omadac.list \
            "${current_backup}/"

    fi

    ###########################################################################
    # MongoDB
    ###########################################################################

    if command -v mongodump >/dev/null 2>&1; then

        mkdir -p "${current_backup}/mongodump"

        log "Executando mongodump..."

        if mongodump \
            --out "${current_backup}/mongodump" \
            >> "${LOG_FILE}" 2>&1; then

            success "Backup MongoDB concluído."

        else

            warning "mongodump retornou erro."

        fi

    else

        warning "mongodump não está disponível."

    fi

    ###########################################################################
    # Compactação
    ###########################################################################

    log "Compactando backup..."

    tar -czf \
        "${current_backup}.tar.gz" \
        -C "${INSTALLER_BACKUP_DIR}" \
        "$(basename "${current_backup}")"

    success "Backup concluído:"
    echo
    echo "${current_backup}.tar.gz"
    echo

}

###############################################################################
# BACKUP EXISTENTE
###############################################################################

list_backups() {

    echo
    echo "=========================================================================="
    echo "                         BACKUPS OMADA"
    echo "=========================================================================="
    echo

    if [[ ! -d "${BACKUP_BASE}" ]]; then

        warning "Diretório de backup não existe:"
        echo "${BACKUP_BASE}"
        return

    fi

    find "${BACKUP_BASE}" \
        -maxdepth 3 \
        \( -type d -o -type f \) \
        -printf '%TY-%Tm-%Td %TH:%TM  %p\n' \
        2>/dev/null \
        | sort -r

    echo

}

###############################################################################
# REMOVER OMADA
###############################################################################

remove_omada() {

    show_header

    echo
    warning "ATENÇÃO"
    echo
    echo "Esta operação removerá o Omada Controller."
    echo
    echo "Os backups em:"
    echo
    echo "    ${BACKUP_BASE}"
    echo
    echo "NÃO serão removidos."
    echo

    read -r -p "Criar backup antes da remoção? [S/n]: " BACKUP_CHOICE

    if [[ ! "${BACKUP_CHOICE,,}" =~ ^n$ ]]; then

        detect_os
        check_architecture

        create_backup

    fi

    echo
    read -r -p "CONFIRMA a remoção do Omada? [s/N]: " ANSWER

    [[ "${ANSWER,,}" == "s" ]] || {

        warning "Operação cancelada."

        return

    }

    log "Parando serviço..."

    systemctl stop omadac 2>/dev/null || true

    log "Desabilitando serviço..."

    systemctl disable omadac 2>/dev/null || true

    log "Removendo pacote..."

    dpkg --remove \
        --force-remove-reinstreq \
        omadac \
        2>/dev/null || true

    dpkg --purge \
        --force-all \
        omadac \
        2>/dev/null || true

    log "Corrigindo estado do APT..."

    dpkg --configure -a || true

    apt-get -f install -y

    ###########################################################################
    # Diretórios conhecidos
    ###########################################################################

    warning "Os diretórios conhecidos do Omada serão removidos."

    rm -rf /opt/tplink
    rm -rf /opt/omada
    rm -rf /etc/omada

    systemctl daemon-reload

    success "Omada removido."

    echo
    log "Backups preservados em:"
    echo "${BACKUP_BASE}"

}

###############################################################################
# DOWNLOAD
###############################################################################

download_package() {

    mkdir -p "${TMP_DIR}"

    rm -f "${TMP_DIR}"/*.deb 2>/dev/null || true

    echo
    echo "Informe a URL DIRETA do pacote oficial .deb do Omada."
    echo

    read -r -p "URL: " OMADA_URL

    [[ -n "${OMADA_URL}" ]] || \
        die "URL não informada."

    [[ "${OMADA_URL}" == *.deb ]] || \
        warning "A URL não termina com .deb. Continuando para validação."

    OMADA_PACKAGE="$(basename "${OMADA_URL%%\?*}")"

    [[ -n "${OMADA_PACKAGE}" ]] || \
        die "Não foi possível determinar o nome do pacote."

    log "Baixando ${OMADA_PACKAGE}..."

    curl \
        -fL \
        --retry 3 \
        --retry-delay 5 \
        --connect-timeout 15 \
        -o "${TMP_DIR}/${OMADA_PACKAGE}" \
        "${OMADA_URL}"

    [[ -s "${TMP_DIR}/${OMADA_PACKAGE}" ]] || \
        die "Arquivo .deb não foi baixado corretamente."

    success "Download concluído."

}

###############################################################################
# VALIDAR PACOTE
###############################################################################

validate_package() {

    local package_path="${TMP_DIR}/${OMADA_PACKAGE}"

    [[ -f "${package_path}" ]] || \
        die "Pacote não encontrado: ${package_path}"

    log "Validando pacote..."

    dpkg-deb --info "${package_path}" >/dev/null 2>&1 || \
        die "O arquivo não é um pacote Debian válido."

    OMADA_VERSION="$(
        dpkg-deb \
            -f "${package_path}" \
            Version
    )"

    local package_arch

    package_arch="$(
        dpkg-deb \
            -f "${package_path}" \
            Architecture
    )"

    log "Versão: ${OMADA_VERSION}"
    log "Arquitetura do pacote: ${package_arch}"

    [[ "${package_arch}" == "amd64" || "${package_arch}" == "all" ]] || \
        die "Arquitetura do pacote incompatível: ${package_arch}"

    success "Pacote validado."

}

###############################################################################
# INSTALAR OMADA
###############################################################################

install_omada() {

    local package_path="${TMP_DIR}/${OMADA_PACKAGE}"

    log "Instalando Omada Controller ${OMADA_VERSION}..."

    if dpkg -i "${package_path}"; then

        success "Pacote instalado pelo dpkg."

    else

        warning "dpkg informou dependências ou configuração pendente."

        log "Executando apt-get -f install..."

        apt-get -f install -y

        log "Tentando novamente..."

        dpkg -i "${package_path}"

    fi

    log "Configurando pacotes..."

    dpkg --configure -a

    apt-get -f install -y

    success "Instalação do pacote concluída."

}

###############################################################################
# CONFIGURAR SERVIÇO
###############################################################################

configure_service() {

    systemctl daemon-reload

    if systemctl list-unit-files \
        | grep -q "^omadac.service"; then

        log "Habilitando serviço omadac..."

        systemctl enable omadac

        log "Iniciando serviço omadac..."

        systemctl restart omadac

        sleep 10

        if systemctl is-active --quiet omadac; then

            success "Omada Controller está ativo."

        else

            warning "Omada Controller não iniciou corretamente."

            echo
            echo "Últimos logs:"
            echo

            journalctl \
                -u omadac \
                --no-pager \
                -n 50 \
                || true

        fi

    else

        warning "Unidade systemd omadac.service não encontrada."

    fi

}

###############################################################################
# STATUS
###############################################################################

show_status() {

    echo
    echo "=========================================================================="
    echo "                     STATUS DO OMADA CONTROLLER"
    echo "=========================================================================="
    echo

    echo "Pacote:"
    dpkg-query \
        -W \
        -f='${Package}: ${Version} - ${Status}\n' \
        omadac \
        2>/dev/null || \
        echo "omadac não instalado."

    echo

    echo "Serviço:"
    systemctl status \
        omadac \
        --no-pager \
        --full \
        2>/dev/null || true

}

###############################################################################
# PORTAS
###############################################################################

show_ports() {

    echo
    echo "=========================================================================="
    echo "                         PORTAS OMADA"
    echo "=========================================================================="
    echo

    local ports

    ports="$(
        ss -lntup 2>/dev/null \
        | grep -E \
        ':8088|:8043|:29810|:29811|:29812|:29813|:29814' \
        || true
    )"

    if [[ -n "${ports}" ]]; then

        echo "${ports}"

    else

        warning "Nenhuma porta conhecida do Omada está em escuta."

    fi

    echo

}

###############################################################################
# PROCESSOS
###############################################################################

show_processes() {

    echo
    echo "Processos relacionados:"
    echo

    ps aux \
        | grep -Ei 'omada|mongod' \
        | grep -v grep \
        || true

    echo

}

###############################################################################
# RESTAURAÇÃO
###############################################################################

restore_backup() {

    show_header

    list_backups

    echo
    read -r -p "Informe o diretório do backup a restaurar: " RESTORE_DIR

    [[ -d "${RESTORE_DIR}" ]] || \
        die "Diretório de backup não encontrado."

    echo
    warning "RESTAURAÇÃO DE BACKUP"
    echo
    echo "Origem:"
    echo "${RESTORE_DIR}"
    echo
    echo "Esta operação poderá substituir dados existentes."
    echo

    read -r -p "CONFIRMA a restauração? [s/N]: " ANSWER

    [[ "${ANSWER,,}" == "s" ]] || {

        warning "Restauração cancelada."

        return

    }

    ###########################################################################
    # Backup de segurança antes da restauração
    ###########################################################################

    log "Criando backup de segurança antes da restauração..."

    create_backup

    ###########################################################################
    # Parar Omada
    ###########################################################################

    log "Parando Omada..."

    systemctl stop omadac 2>/dev/null || true

    ###########################################################################
    # MongoDB
    ###########################################################################

    if [[ -d "${RESTORE_DIR}/mongodump" ]]; then

        if command -v mongorestore >/dev/null 2>&1; then

            log "Backup MongoDB encontrado."

            echo
            warning "A restauração MongoDB será executada sem --drop."
            echo

            read -r -p \
                "Executar mongorestore? [s/N]: " MONGO_ANSWER

            if [[ "${MONGO_ANSWER,,}" == "s" ]]; then

                mongorestore \
                    "${RESTORE_DIR}/mongodump"

                success "mongorestore concluído."

            else

                warning "Restauração MongoDB ignorada."

            fi

        else

            warning "mongorestore não está instalado."

        fi

    else

        warning "Nenhum mongodump encontrado no backup."

    fi

    ###########################################################################
    # Arquivos
    ###########################################################################

    if [[ -d "${RESTORE_DIR}/files" ]]; then

        warning "Backup de arquivos encontrado."

        read -r -p \
            "Restaurar arquivos do backup? [s/N]: " FILE_ANSWER

        if [[ "${FILE_ANSWER,,}" == "s" ]]; then

            cp -a \
                "${RESTORE_DIR}/files/." \
                /opt/

            success "Arquivos restaurados."

        else

            warning "Restauração dos arquivos ignorada."

        fi

    fi

    ###########################################################################
    # Iniciar Omada
    ###########################################################################

    systemctl daemon-reload

    if systemctl list-unit-files \
        | grep -q "^omadac.service"; then

        systemctl restart omadac 2>/dev/null || true

    fi

    success "Processo de restauração finalizado."

}

###############################################################################
# DIAGNÓSTICO
###############################################################################

diagnostics() {

    show_header

    echo
    echo "=========================================================================="
    echo "                       DIAGNÓSTICO OMADA"
    echo "=========================================================================="
    echo

    detect_os
    check_architecture

    echo
    echo "Java:"
    java -version 2>&1 || true

    echo
    echo "MongoDB:"
    check_mongodb

    echo
    echo "Pacote Omada:"
    dpkg-query \
        -W \
        -f='${Package} ${Version} ${Status}\n' \
        omadac \
        2>/dev/null || true

    echo
    echo "Serviço:"
    systemctl status omadac \
        --no-pager \
        --full \
        2>/dev/null || true

    echo
    echo "Portas:"
    show_ports

    echo
    echo "Processos:"
    show_processes

    echo
    echo "Diretórios:"
    find_omada_directories

    echo
    echo "Backups:"
    list_backups

}

###############################################################################
# DRY RUN
###############################################################################

dry_run() {

    show_header

    echo
    echo "=========================================================================="
    echo "                         DRY RUN"
    echo "=========================================================================="
    echo

    warning "Nenhuma alteração será realizada."
    echo

    detect_os
    check_architecture

    echo
    log "Verificando Java..."

    if command -v java >/dev/null 2>&1; then

        java -version 2>&1

    else

        warning "Java não instalado."

    fi

    echo
    log "Verificando Omada..."

    detect_omada

    echo
    log "Verificando MongoDB..."

    check_mongodb

    echo
    log "Verificando diretórios..."

    find_omada_directories

    echo
    log "Verificando backups..."

    list_backups

    echo
    success "Dry-run concluído."

}

###############################################################################
# INSTALAÇÃO COMPLETA
###############################################################################

full_install() {

    show_header

    detect_os
    check_architecture
    check_internet

    echo
    install_dependencies
    check_java

    echo
    detect_omada

    echo
    warning "Será criado um backup antes da instalação."
    echo

    read -r -p "Continuar? [S/n]: " ANSWER

    if [[ "${ANSWER,,}" == "n" ]]; then

        warning "Instalação cancelada."

        return

    fi

    create_backup

    download_package

    validate_package

    install_omada

    configure_service

    show_status

    show_ports

    echo
    echo "=========================================================================="
    success "INSTALAÇÃO CONCLUÍDA"
    echo "=========================================================================="
    echo

    local server_ip

    server_ip="$(
        hostname -I 2>/dev/null \
        | awk '{print $1}'
    )"

    [[ -n "${server_ip}" ]] || \
        server_ip="IP_DO_SERVIDOR"

    echo "Acesso ao Omada:"
    echo
    echo "  https://${server_ip}:8043"
    echo
    echo "Portal de gerenciamento:"
    echo
    echo "  http://${server_ip}:8088"
    echo
    echo "Serviço:"
    echo
    echo "  systemctl status omadac"
    echo
    echo "Logs:"
    echo
    echo "  journalctl -u omadac -f"
    echo
    echo "Log do instalador:"
    echo
    echo "  ${LOG_FILE}"
    echo
    echo "=========================================================================="

}

###############################################################################
# MENU
###############################################################################

show_menu() {

    while true; do

        show_header

        echo "1) Instalação completa"
        echo "2) Criar backup"
        echo "3) Listar backups"
        echo "4) Restaurar backup"
        echo "5) Remover Omada"
        echo "6) Status do Omada"
        echo "7) Ver portas"
        echo "8) Diagnóstico completo"
        echo "9) Dry-run"
        echo "10) Ver versão"
        echo "0) Sair"
        echo

        read -r -p "Selecione uma opção: " OPTION

        case "${OPTION}" in

            1)
                full_install
                read -r -p "Pressione ENTER para continuar..."
                ;;

            2)
                create_backup
                read -r -p "Pressione ENTER para continuar..."
                ;;

            3)
                list_backups
                read -r -p "Pressione ENTER para continuar..."
                ;;

            4)
                restore_backup
                read -r -p "Pressione ENTER para continuar..."
                ;;

            5)
                remove_omada
                read -r -p "Pressione ENTER para continuar..."
                ;;

            6)
                show_status
                read -r -p "Pressione ENTER para continuar..."
                ;;

            7)
                show_ports
                read -r -p "Pressione ENTER para continuar..."
                ;;

            8)
                diagnostics
                read -r -p "Pressione ENTER para continuar..."
                ;;

            9)
                DRY_RUN=true
                dry_run
                read -r -p "Pressione ENTER para continuar..."
                ;;

            10)
                echo
                echo "${SCRIPT_NAME} ${SCRIPT_VERSION}"
                echo "CTIC-BTC - IFMA Campus Buriticupu"
                echo "Criador: Adriano Freire"
                echo
                read -r -p "Pressione ENTER para continuar..."
                ;;

            0)
                echo
                success "Encerrando."
                exit 0
                ;;

            *)
                warning "Opção inválida."
                sleep 2
                ;;

        esac

    done

}

###############################################################################
# ARGUMENTOS
###############################################################################

show_help() {

    cat <<EOF

${SCRIPT_NAME} ${SCRIPT_VERSION}

CTIC-BTC - IFMA Campus Buriticupu
Criador: Adriano Freire

USO:

  $0
      Menu interativo

  $0 --install
      Instalação completa

  $0 --backup
      Criar backup

  $0 --list-backups
      Listar backups

  $0 --restore
      Restaurar backup

  $0 --remove
      Remover Omada

  $0 --status
      Mostrar status

  $0 --ports
      Mostrar portas

  $0 --diagnostic
      Diagnóstico completo

  $0 --dry-run
      Executar diagnóstico sem alterações

  $0 --version
      Mostrar versão

  $0 --help
      Mostrar esta ajuda

EOF

}

###############################################################################
# MAIN
###############################################################################

initialize_log
check_root

case "${1:-}" in

    "")
        show_menu
        ;;

    --install)
        full_install
        ;;

    --backup)
        detect_os
        check_architecture
        create_backup
        ;;

    --list-backups)
        list_backups
        ;;

    --restore)
        restore_backup
        ;;

    --remove)
        remove_omada
        ;;

    --status)
        show_status
        ;;

    --ports)
        show_ports
        ;;

    --diagnostic)
        diagnostics
        ;;

    --dry-run)
        dry_run
        ;;

    --version)
        echo "${SCRIPT_NAME} ${SCRIPT_VERSION}"
        echo "CTIC-BTC - IFMA Campus Buriticupu"
        echo "Criador: Adriano Freire"
        ;;

    --help|-h)
        show_help
        ;;

    *)
        die "Opção desconhecida: $1

Use:

$0 --help"

        ;;

esac

###############################################################################
# FIM
###############################################################################
```
