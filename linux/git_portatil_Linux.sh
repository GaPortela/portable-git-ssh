#!/usr/bin/env bash

# ============================================================
# GIT PORTATIL - LINUX
#
# Arquitetura:
#   - Este script NAO depende de Konsole, GNOME Terminal etc.
#   - A entrada universal e feita com: bash git_portatil_Linux.sh
#   - O script se relanca por uma copia em /tmp antes de desmontar
#     o pendrive, sem copiar a chave privada.
#
# Estrutura relativa esperada:
#   DIRETORIO_PAI/.env
#   DIRETORIO_PAI/id_ed25519
#   DIRETORIO_PAI/linux/git_portatil_Linux.sh
#   DIRETORIO_PAI/linux/git_portatil_Linux.desktop
#
# DIRETORIO_PAI pode ter qualquer nome e estar em qualquer local do
# pendrive. O importante e que .env e id_ed25519 estejam no diretorio
# pai da pasta linux. .env.example, id_ed25519.pub e README-Linux.md
# podem acompanhar essa estrutura, mas nao sao necessarios para executar.
#
# O arquivo .desktop e apenas um atalho opcional. Em VFAT, opcoes como
# showexec podem impedir que ambientes graficos autorizem sua execucao.
# Antes de desmontar o pendrive, este script se relanca por uma copia
# temporaria e preserva o caminho original via --original-script.

# Permite executar inclusive como:
#   sh git_portatil_Linux.sh
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

ORIGINAL_SCRIPT=""

if [ "${1:-}" = "--original-script" ]; then
    ORIGINAL_SCRIPT="${2:-}"
    shift 2
fi

set -u

EXECUTED_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

if [ -n "$ORIGINAL_SCRIPT" ]; then
    if [ ! -f "$ORIGINAL_SCRIPT" ]; then
        echo "[ERRO] Script original nao encontrado:"
        echo "       $ORIGINAL_SCRIPT"
        exit 1
    fi
    SCRIPT_PATH="$(readlink -f "$ORIGINAL_SCRIPT")"
else
    SCRIPT_PATH="$EXECUTED_SCRIPT_PATH"
fi

SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
PENDRIVE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# A copia ja esta aberta pelo Bash e pode ser removida imediatamente.
# O descritor aberto continua valido, sem deixar o helper em /tmp.
case "$EXECUTED_SCRIPT_PATH" in
    /tmp/git-portatil-relaunch.*.sh)
        [ -z "$ORIGINAL_SCRIPT" ] || rm -f -- "$EXECUTED_SCRIPT_PATH" 2>/dev/null || true
        ;;
esac

CHAVE_PATH="${PENDRIVE_ROOT}/id_ed25519"
ENV_PATH="${PENDRIVE_ROOT}/.env"

GIT_NAME=""
GIT_EMAIL=""

# ------------------------------------------------------------
# Configuracao
# ------------------------------------------------------------

read_env_value() {
    local key="$1"
    local line value

    line="$(grep -m1 -E "^[[:space:]]*${key}[[:space:]]*=" "$ENV_PATH" 2>/dev/null || true)"
    [ -n "$line" ] || return 1

    value="${line#*=}"
    value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac

    printf '%s\n' "$value"
}

load_config() {
    if [ ! -f "$ENV_PATH" ]; then
        echo "[ERRO] Arquivo .env nao encontrado em:"
        echo "       $ENV_PATH"
        echo
        echo "Copie .env.example para .env na raiz do pendrive e configure:"
        echo "  GIT_USER_NAME=Seu Nome"
        echo "  GIT_USER_EMAIL=seu@email.com"
        return 1
    fi

    GIT_NAME="$(read_env_value GIT_USER_NAME || true)"
    GIT_EMAIL="$(read_env_value GIT_USER_EMAIL || true)"

    if [ -z "$GIT_NAME" ]; then
        echo "[ERRO] GIT_USER_NAME nao foi definido corretamente em:"
        echo "       $ENV_PATH"
        return 1
    fi

    if [ -z "$GIT_EMAIL" ]; then
        echo "[ERRO] GIT_USER_EMAIL nao foi definido corretamente em:"
        echo "       $ENV_PATH"
        return 1
    fi
}

# ------------------------------------------------------------
# Utilitarios
# ------------------------------------------------------------

normalize_path() {
    local path="$1"
    path="${path#\'}"; path="${path%\'}"
    path="${path#\"}"; path="${path%\"}"
    printf '%s\n' "$path"
}

is_ssh_url() {
    local url="$1"
    local normalized_url="${url,,}"

    case "$normalized_url" in
        *[[:space:]]*) return 1 ;;
        ssh://?*/?*) return 0 ;;
        *://*) return 1 ;;
        ?*@?*:?*) return 0 ;;
        *) return 1 ;;
    esac
}

mode_is_ssh_safe() {
    local mode="$1"

    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1

    # OpenSSH rejeita a chave quando grupo/outros possuem acesso.
    # Exemplos aceitos por este teste: 600, 400, 700.
    (( (8#$mode & 077) == 0 ))
}

# ------------------------------------------------------------
# Permissoes da chave / VFAT / exFAT
# ------------------------------------------------------------

RECOVERY_ARMED=0
RECOVERY_SOURCE=""
RECOVERY_TARGET=""
RECOVERY_FSTYPE=""
RECOVERY_OPTIONS=""
RECOVERY_REPLACE_CURRENT=0

path_is_inside() {
    local path="$1"
    local root="$2"

    case "${path%/}/" in
        "${root%/}/"*) return 0 ;;
        *) return 1 ;;
    esac
}

build_mount_options() {
    local original_options="$1"
    local secure_permissions="$2"
    local option
    local -a mount_options=()
    local -a preserved_options=()

    IFS=',' read -r -a mount_options <<< "$original_options"

    for option in "${mount_options[@]}"; do
        case "$option" in
            ""|remount|defaults|auto|noauto|nofail|user|users|owner|group|seclabel|uhelper=*|x-*|X-*)
                ;;
            user_id=*|group_id=*|default_permissions|allow_other|blksize=*)
                ;;
            uid=*|gid=*|fmask=*|dmask=*|umask=*)
                if [ "$secure_permissions" != "yes" ]; then
                    preserved_options+=("$option")
                fi
                ;;
            showexec)
                # Em VFAT, showexec retira o bit de execucao de .sh e
                # .desktop. Preserve apenas ao reconstruir a montagem
                # original; a montagem segura deve permitir esses arquivos.
                if [ "$secure_permissions" != "yes" ]; then
                    preserved_options+=("$option")
                fi
                ;;
            *)
                preserved_options+=("$option")
                ;;
        esac
    done

    if [ "$secure_permissions" = "yes" ]; then
        preserved_options+=(
            "uid=$(id -u)"
            "gid=$(id -g)"
            "fmask=0077"
            "dmask=0077"
        )
    fi

    local IFS=','
    printf '%s\n' "${preserved_options[*]}"
}

restore_original_mount() {
    local replace_current="${1:-auto}"

    [ "$RECOVERY_ARMED" -eq 1 ] || return 0

    if [ "$replace_current" = "auto" ]; then
        if [ "$RECOVERY_REPLACE_CURRENT" -eq 1 ]; then
            replace_current="yes"
        else
            replace_current="no"
        fi
    fi

    echo
    echo "[INFO] Tentando restaurar a montagem original..."

    if mountpoint -q "$RECOVERY_TARGET"; then
        if [ "$replace_current" != "yes" ]; then
            echo "[INFO] O dispositivo continua montado; nenhuma restauracao e necessaria."
            return 0
        fi

        if ! sudo umount -- "$RECOVERY_TARGET"; then
            echo "[ERRO] Nao foi possivel remover a montagem incompleta."
            return 1
        fi
    fi

    if [ -L "$RECOVERY_TARGET" ]; then
        echo "[ERRO] O mountpoint foi substituido por um link simbolico:"
        echo "       $RECOVERY_TARGET"
        return 1
    fi

    sudo mkdir -p -- "$RECOVERY_TARGET" || return 1

    if sudo mount -t "$RECOVERY_FSTYPE" \
        -o "$RECOVERY_OPTIONS" \
        "$RECOVERY_SOURCE" \
        "$RECOVERY_TARGET"; then
        echo "[OK] Montagem original restaurada."
        return 0
    fi

    echo "[ERRO] Nao foi possivel restaurar automaticamente a montagem original."
    echo "[INFO] Dispositivo: $RECOVERY_SOURCE"
    echo "[INFO] Mountpoint:  $RECOVERY_TARGET"
    return 1
}

clear_mount_recovery() {
    RECOVERY_ARMED=0
    RECOVERY_REPLACE_CURRENT=0
    trap - EXIT HUP INT TERM
}

recover_mount_and_clear() {
    local replace_current="${1:-auto}"

    if restore_original_mount "$replace_current"; then
        clear_mount_recovery
        return 0
    fi

    echo "[AVISO] O rollback sera tentado novamente ao encerrar o script."
    return 1
}

arm_mount_recovery() {
    RECOVERY_ARMED=1
    RECOVERY_REPLACE_CURRENT=0
    trap 'restore_original_mount auto' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

show_mount_users() {
    local mount_target="$1"

    if command -v fuser >/dev/null 2>&1; then
        echo
        echo "[INFO] Processos relacionados ao mountpoint:"
        sudo fuser -vm "$mount_target" 2>/dev/null || true
    fi
}

ensure_execution_outside_mount() {
    local mount_target="$1"
    shift

    local current_cwd parent_cwd temp_script

    current_cwd="$(pwd -P)"
    parent_cwd="$(readlink -f "/proc/$PPID/cwd" 2>/dev/null || true)"

    if [ -n "$parent_cwd" ] && path_is_inside "$parent_cwd" "$mount_target"; then
        echo "[ERRO] O processo que iniciou este script esta dentro do pendrive:"
        echo "       $parent_cwd"
        echo
        echo "[INFO] Feche este terminal e abra outro fora do pendrive."
        echo "[INFO] Depois execute: bash \"$SCRIPT_PATH\""
        return 1
    fi

    if path_is_inside "$current_cwd" "$mount_target"; then
        cd /tmp || return 1
    fi

    if path_is_inside "$EXECUTED_SCRIPT_PATH" "$mount_target"; then
        temp_script="$(mktemp /tmp/git-portatil-relaunch.XXXXXX.sh)" || {
            echo "[ERRO] Nao foi possivel criar a copia temporaria do script."
            return 1
        }

        if ! cp -- "$SCRIPT_PATH" "$temp_script" || ! chmod 700 "$temp_script"; then
            rm -f -- "$temp_script"
            echo "[ERRO] Nao foi possivel preparar a copia temporaria do script."
            return 1
        fi

        cd /tmp || return 1
        exec bash "$temp_script" --original-script "$SCRIPT_PATH" "$@"
    fi

    return 0
}

validate_secure_mount() {
    local expected_source="$1"
    local mount_target="$2"
    local current_source current_options current_mode current_owner

    if ! mountpoint -q "$mount_target"; then
        echo "[ERRO] O mountpoint nao esta montado apos a operacao."
        return 1
    fi

    if [ ! -f "$CHAVE_PATH" ] || [ ! -f "$SCRIPT_PATH" ]; then
        echo "[ERRO] A chave ou o script original nao foi encontrado apos a montagem."
        return 1
    fi

    current_source="$(findmnt -n -f -o SOURCE -T "$CHAVE_PATH" 2>/dev/null || true)"
    current_source="${current_source%%[*}"
    current_source="$(readlink -f "$current_source" 2>/dev/null || printf '%s' "$current_source")"

    if [ "$current_source" != "$expected_source" ]; then
        echo "[ERRO] O dispositivo montado nao corresponde ao dispositivo original."
        return 1
    fi

    current_options="$(findmnt -n -f -o OPTIONS -T "$CHAVE_PATH" 2>/dev/null || true)"
    current_mode="$(stat -c '%a' "$CHAVE_PATH" 2>/dev/null || true)"
    current_owner="$(stat -c '%u' "$CHAVE_PATH" 2>/dev/null || true)"

    if ! mode_is_ssh_safe "$current_mode" || [ "$current_owner" != "$(id -u)" ]; then
        echo "[ERRO] A chave continua com dono ou permissoes inseguras."
        echo "[INFO] Dono/modo detectados: ${current_owner:-?}/${current_mode:-?}"
        return 1
    fi

    if ! [[ ",$current_options," =~ ,fmask=0*77, ]] ||
       ! [[ ",$current_options," =~ ,dmask=0*77, ]]; then
        echo "[ERRO] A montagem nao confirmou fmask=0077,dmask=0077."
        echo "[INFO] Opcoes detectadas: ${current_options:-desconhecidas}"
        return 1
    fi

    echo "[OK] Chave protegida: dono=$current_owner, modo=$current_mode."
    echo "[INFO] Opcoes atuais: $current_options"
    return 0
}

prepare_key_permissions() {
    local current_mode current_owner mount_target mount_source fstype options
    local mount_fstype filesystem_signature original_options secure_options

    if [ ! -f "$CHAVE_PATH" ]; then
        echo "[ERRO] Chave SSH nao encontrada:"
        echo "       $CHAVE_PATH"
        return 1
    fi

    # Em filesystems Unix isto normalmente resolve diretamente.
    chmod 600 "$CHAVE_PATH" 2>/dev/null || true

    current_mode="$(stat -c '%a' "$CHAVE_PATH" 2>/dev/null || true)"
    current_owner="$(stat -c '%u' "$CHAVE_PATH" 2>/dev/null || true)"
    if mode_is_ssh_safe "$current_mode" && [ "$current_owner" = "$(id -u)" ]; then
        echo "[OK] Permissoes da chave SSH estao seguras ($current_mode)."
        return 0
    fi

    echo
    echo "[AVISO] A chave SSH continua com permissao ${current_mode:-desconhecida}."
    echo "[INFO] Verificando o filesystem do pendrive..."

    for cmd in findmnt mount mountpoint umount stat sudo readlink mktemp cp sync; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "[ERRO] Comando necessario nao encontrado: $cmd"
            return 1
        fi
    done

    mount_target="$(findmnt -n -f -o TARGET -T "$CHAVE_PATH" 2>/dev/null || true)"
    mount_source="$(findmnt -n -f -o SOURCE -T "$CHAVE_PATH" 2>/dev/null || true)"
    fstype="$(findmnt -n -f -o FSTYPE -T "$CHAVE_PATH" 2>/dev/null || true)"
    options="$(findmnt -n -f -o OPTIONS -T "$CHAVE_PATH" 2>/dev/null || true)"
    mount_source="${mount_source%%[*}"
    mount_source="$(readlink -f "$mount_source" 2>/dev/null || printf '%s' "$mount_source")"

    echo "[INFO] Dispositivo: ${mount_source:-desconhecido}"
    echo "[INFO] Mountpoint:  ${mount_target:-desconhecido}"
    echo "[INFO] Filesystem:  ${fstype:-desconhecido}"

    filesystem_signature="$fstype"
    case "$fstype" in
        fuseblk|fuse.exfat*)
            if command -v blkid >/dev/null 2>&1; then
                filesystem_signature="$(blkid -o value -s TYPE "$mount_source" 2>/dev/null || true)"
            fi
            ;;
    esac

    case "$filesystem_signature" in
        vfat|fat|msdos) mount_fstype="vfat" ;;
        exfat) mount_fstype="exfat" ;;
        *)
            echo "[ERRO] Nao foi possivel garantir permissoes seguras para a chave."
            echo "[INFO] Filesystem detectado: ${fstype:-desconhecido}"
            echo "[INFO] Opcoes de montagem: ${options:-desconhecidas}"
            return 1
            ;;
    esac

    case "$filesystem_signature" in
        vfat|fat|msdos|exfat)
            if [ -z "$mount_target" ] || [ -z "$mount_source" ] || [ -z "$options" ]; then
                echo "[ERRO] Nao foi possivel determinar SOURCE/TARGET/OPTIONS da montagem."
                return 1
            fi

            if [ "$mount_target" = "/" ] || ! path_is_inside "$CHAVE_PATH" "$mount_target"; then
                echo "[ERRO] Mountpoint inseguro ou inconsistente: $mount_target"
                return 1
            fi

            if [ ! -b "$mount_source" ]; then
                echo "[ERRO] A origem da montagem nao e um dispositivo de bloco:"
                echo "       $mount_source"
                return 1
            fi

            ensure_execution_outside_mount "$mount_target" "$@" || return 1

            echo
            echo "[INFO] $filesystem_signature nao armazena permissoes Unix por arquivo."
            echo "[INFO] O pendrive sera desmontado e montado novamente com:"
            echo "       uid=$(id -u),gid=$(id -g),fmask=0077,dmask=0077"
            echo

            if ! sudo -v; then
                echo "[ERRO] Nao foi possivel validar o sudo."
                return 1
            fi

            original_options="$(build_mount_options "$options" no)"
            secure_options="$(build_mount_options "$options" yes)"

            if [ -z "$original_options" ] || [ -z "$secure_options" ]; then
                echo "[ERRO] Nao foi possivel preparar as opcoes de montagem."
                return 1
            fi

            RECOVERY_SOURCE="$mount_source"
            RECOVERY_TARGET="$mount_target"
            RECOVERY_FSTYPE="$mount_fstype"
            RECOVERY_OPTIONS="$original_options"

            cd /tmp || return 1
            sync
            arm_mount_recovery

            echo "[INFO] Desmontando: $mount_target"
            if ! sudo umount -- "$mount_target"; then
                clear_mount_recovery
                echo "[ERRO] Nao foi possivel desmontar o pendrive."
                echo "[INFO] Algum processo ainda esta usando o mountpoint."
                show_mount_users "$mount_target"
                return 1
            fi

            # A partir daqui qualquer montagem presente no alvo deve ser
            # removida antes de restaurar as opcoes originais.
            RECOVERY_REPLACE_CURRENT=1

            if mountpoint -q "$mount_target"; then
                echo "[ERRO] O mountpoint continua ocupado apos o umount."
                recover_mount_and_clear || true
                return 1
            fi

            if [ -L "$mount_target" ]; then
                echo "[ERRO] O mountpoint foi substituido por um link simbolico."
                recover_mount_and_clear || true
                return 1
            fi

            if ! sudo mkdir -p -- "$mount_target"; then
                recover_mount_and_clear || true
                return 1
            fi

            if [ -L "$mount_target" ]; then
                echo "[ERRO] O mountpoint foi substituido por um link simbolico."
                recover_mount_and_clear || true
                return 1
            fi

            echo "[INFO] Montando novamente com permissoes restritas..."
            if ! sudo mount -t "$mount_fstype" \
                -o "$secure_options" \
                "$mount_source" \
                "$mount_target"; then
                echo "[ERRO] Falha ao montar novamente o pendrive."
                recover_mount_and_clear || true
                return 1
            fi

            if ! validate_secure_mount "$mount_source" "$mount_target"; then
                recover_mount_and_clear yes || true
                return 1
            fi

            clear_mount_recovery
            return 0
            ;;
    esac
}

# ------------------------------------------------------------
# Git
# ------------------------------------------------------------

check_git() {
    echo "[INFO] Verificando Git e OpenSSH..."

    if command -v git >/dev/null 2>&1 && command -v ssh >/dev/null 2>&1; then
        echo "[OK] Git e OpenSSH operacionais."
        return 0
    fi

    echo "[AVISO] Git ou OpenSSH nao localizado. Tentando instalar..."

    if [ -f /etc/arch-release ]; then
        sudo pacman -Sy --noconfirm git openssh
    elif [ -f /etc/debian_version ]; then
        sudo apt update && sudo apt install -y git openssh-client
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y git openssh-clients
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper --non-interactive install git openssh-clients
    else
        echo "[ERRO] Nao foi possivel detectar um gerenciador suportado."
        return 1
    fi

    if ! command -v git >/dev/null 2>&1 || ! command -v ssh >/dev/null 2>&1; then
        echo "[ERRO] Git ou OpenSSH continua indisponivel apos a instalacao."
        return 1
    fi
}

configure_repo() {
    local repo="$1"

    if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
        echo "[ERRO] O caminho informado nao e um repositorio Git valido:"
        echo "       $repo"
        return 1
    fi

    git -C "$repo" config --local core.sshCommand \
        "ssh -i '${CHAVE_PATH}' -o IdentitiesOnly=yes" || return 1
    git -C "$repo" config --local user.name "$GIT_NAME" || return 1
    git -C "$repo" config --local user.email "$GIT_EMAIL" || return 1
}

prepare_clone_destination() {
    local base_dir="$1"
    local repo_name="$2"
    local target_dir="${base_dir%/}/$repo_name"

    if [ -e "$target_dir" ]; then
        echo "[ERRO] O destino ja existe:"
        echo "       $target_dir"
        return 1
    fi

    if [ -w "$base_dir" ]; then
        return 0
    fi

    echo
    echo "[INFO] Sem permissao de escrita em:"
    echo "       $base_dir"
    echo "[INFO] Sudo sera usado somente para preparar:"
    echo "       $target_dir"
    echo

    sudo mkdir -p "$target_dir" || return 1

    if ! sudo chown "$(id -u):$(id -g)" "$target_dir"; then
        sudo rmdir "$target_dir" 2>/dev/null || true
        return 1
    fi
}

clone_repo() {
    local url folder_name clone_input clone_path

    check_git || return

    while true; do
        echo
        read -r -p "URL SSH (git@github.com:usuario/projeto.git): " url

        if [ -z "$url" ]; then
            echo "[ERRO] URL vazia."
            return
        fi

        if is_ssh_url "$url"; then
            break
        fi

        echo "[ERRO] URL invalida. HTTP/HTTPS e outros formatos nao sao aceitos."
        echo "[INFO] Informe uma URL SSH, por exemplo:"
        echo "       git@github.com:usuario/projeto.git"
    done

    folder_name="$(basename -s .git "$url")"

    echo
    read -r -p "Diretorio para clonar [Enter = $HOME]: " clone_input

    if [ -z "$clone_input" ]; then
        clone_path="$HOME"
    else
        clone_path="$(normalize_path "$clone_input")"
    fi

    if [ ! -d "$clone_path" ]; then
        echo "[ERRO] Diretorio nao encontrado:"
        echo "       $clone_path"
        return
    fi

    prepare_clone_destination "$clone_path" "$folder_name" || return

    cd "$clone_path" || return

    echo
    echo "[INFO] Clonando $folder_name em:"
    echo "       $clone_path"

    if ! git -c core.sshCommand="ssh -i '${CHAVE_PATH}' -o IdentitiesOnly=yes" \
        clone "$url" "$folder_name"; then
        return
    fi

    cd "$folder_name" || return
    if ! configure_repo "$(pwd)"; then
        echo "[ERRO] O clone terminou, mas a configuracao local falhou."
        return
    fi

    echo
    echo "[SUCESSO] Repositorio clonado e configurado."
    echo "Local: $(pwd)"
    echo "Identidade: $GIT_NAME <$GIT_EMAIL>"
    echo
    git status
}

config_existing_repo() {
    local folder

    read -r -p "Caminho do repositorio: " folder
    folder="$(normalize_path "$folder")"

    if ! configure_repo "$folder"; then
        return
    fi

    cd "$folder" || return

    echo "[SUCESSO] Repositorio configurado."
    echo "Local: $(pwd)"
    echo "Identidade: $GIT_NAME <$GIT_EMAIL>"
}

test_ssh() {
    echo
    echo "[INFO] Testando autenticacao SSH..."
    ssh -i "$CHAVE_PATH" \
        -o IdentitiesOnly=yes \
        -o IdentityAgent=none \
        -T git@github.com
}

# ------------------------------------------------------------
# Inicializacao
# ------------------------------------------------------------

load_config || exit 1
prepare_key_permissions "$@" || exit 1

export GIT_SSH_COMMAND="ssh -i '${CHAVE_PATH}' -o IdentitiesOnly=yes -o IdentityAgent=none"

while true; do
    echo
    echo "=========================================="
    echo "          GIT PORTATIL - LINUX"
    echo "=========================================="
    echo "Pendrive:   $PENDRIVE_ROOT"
    echo "Identidade: $GIT_NAME <$GIT_EMAIL>"
    echo
    echo "1. Clonar um novo repositorio"
    echo "2. Configurar um repositorio existente"
    echo "3. Testar autenticacao SSH"
    echo "4. Sair"
    echo

    read -r -p "Escolha uma opcao: " opt

    case "$opt" in
        1) clone_repo ;;
        2) config_existing_repo ;;
        3) test_ssh ;;
        4) exit 0 ;;
        *) echo "[ERRO] Opcao invalida." ;;
    esac
done
