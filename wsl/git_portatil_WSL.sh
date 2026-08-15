#!/usr/bin/env bash

# Se este arquivo for chamado incorretamente com "sh script.sh",
# reexecuta automaticamente usando Bash antes de qualquer sintaxe Bash.
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -u

# ============================================================
# GIT PORTATIL - WSL / UBUNTU
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PENDRIVE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHAVE_PATH="${PENDRIVE_ROOT}/id_ed25519"
ENV_PATH="${PENDRIVE_ROOT}/.env"

GIT_NAME=""
GIT_EMAIL=""

pause_menu() {
    echo
    read -r -p "Pressione Enter para continuar..." _
    echo
}

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
        echo "[ERRO] Arquivo .env nao encontrado:"
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

get_mount_point() {
    if [[ "$PENDRIVE_ROOT" =~ ^/mnt/[^/]+$ ]]; then
        printf '%s\n' "$PENDRIVE_ROOT"
        return 0
    fi

    if [[ "$PENDRIVE_ROOT" == /mnt/* ]]; then
        printf '/mnt/%s\n' "$(printf '%s' "$PENDRIVE_ROOT" | cut -d/ -f3)"
        return 0
    fi

    return 1
}

check_pendrive_mount() {
    local mount_point

    if ! mount_point="$(get_mount_point)"; then
        echo "[ERRO] Nao foi possivel determinar o ponto de montagem do pendrive."
        echo "       Raiz detectada: $PENDRIVE_ROOT"
        return 1
    fi

    if ! mountpoint -q "$mount_point"; then
        echo "[ERRO] O pendrive nao esta montado corretamente em $mount_point."
        echo "       Execute montar_wsl.ps1 pelo Windows e tente novamente."
        return 1
    fi

    if ! awk -v mp="$mount_point" \
        '$2 == mp && $4 ~ /metadata/ {found=1} END {exit !found}' \
        /proc/mounts; then
        echo "[ERRO] $mount_point esta montado sem a opcao metadata."
        echo "       Execute montar_wsl.ps1 para remontar corretamente."
        return 1
    fi
}

prepare_key() {
    check_pendrive_mount || return 1

    if [ ! -f "$CHAVE_PATH" ]; then
        echo "[ERRO] Chave SSH nao encontrada:"
        echo "       $CHAVE_PATH"
        return 1
    fi

    if ! chmod 600 "$CHAVE_PATH"; then
        echo "[ERRO] Nao foi possivel aplicar chmod 600 na chave."
        return 1
    fi

    export GIT_SSH_COMMAND="ssh -i '$CHAVE_PATH' -o IdentitiesOnly=yes -o IdentityAgent=none"
}

check_git() {
    echo "[INFO] Verificando Git..."

    if command -v git >/dev/null 2>&1 && command -v ssh >/dev/null 2>&1; then
        echo "[OK] $(git --version)"
        return 0
    fi

    echo "[AVISO] Git/OpenSSH nao encontrado. Instalando..."
    sudo apt update && sudo apt install -y git openssh-client
}

normalize_path() {
    local path="$1"

    path="${path#\'}"
    path="${path%\'}"
    path="${path#\"}"
    path="${path%\"}"

    if [[ "$path" =~ ^[A-Za-z]:\\ ]] && command -v wslpath >/dev/null 2>&1; then
        wslpath -u "$path" 2>/dev/null || printf '%s\n' "$path"
    else
        printf '%s\n' "$path"
    fi
}

configure_repo() {
    local repo="$1"

    if [ ! -d "$repo/.git" ]; then
        echo "[ERRO] O caminho informado nao contem um repositorio Git:"
        echo "       $repo"
        return 1
    fi

    (
        cd "$repo" || exit 1
        git config --local core.sshCommand \
            "ssh -i '$CHAVE_PATH' -o IdentitiesOnly=yes -o IdentityAgent=none" || exit 1
        git config --local user.name "$GIT_NAME" || exit 1
        git config --local user.email "$GIT_EMAIL" || exit 1
    )
}

open_terminal() {
    local dir="$1"
    local proj_name="$2"
    local distro="${WSL_DISTRO_NAME:-Ubuntu}"
    local windows_dir

    if command -v wt.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
        echo "[INFO] Abrindo nova aba do Windows Terminal..."
        windows_dir="$(wslpath -w "$dir" 2>/dev/null)"

        if [ -n "$windows_dir" ]; then
            wt.exe -w 0 new-tab \
                --title "Git: $proj_name" \
                --startingDirectory "$windows_dir" \
                wsl.exe -d "$distro" \
                >/dev/null 2>&1 &
        else
            echo "[AVISO] Nao foi possivel converter o caminho para o Windows Terminal."
            echo "[INFO] Repositorio configurado em:"
            echo "       $dir"
        fi
    else
        echo "[INFO] Windows Terminal nao encontrado."
        echo "[INFO] Repositorio configurado em:"
        echo "       $dir"
    fi
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
    echo "[INFO] O usuario atual nao possui permissao de escrita em:"
    echo "       $base_dir"
    echo "[INFO] Sera solicitado sudo somente para preparar:"
    echo "       $target_dir"
    echo

    if ! sudo mkdir -p "$target_dir"; then
        echo "[ERRO] Nao foi possivel criar o diretorio com sudo."
        return 1
    fi

    if ! sudo chown "$(id -u):$(id -g)" "$target_dir"; then
        echo "[ERRO] Nao foi possivel transferir a propriedade do diretorio."
        sudo rmdir "$target_dir" 2>/dev/null || true
        return 1
    fi

    return 0
}

clone_repo() {
    check_git || { pause_menu; return; }
    prepare_key || { pause_menu; return; }

    echo
    read -r -p "URL SSH (git@github.com:usuario/projeto.git): " url

    if [ -z "$url" ]; then
        echo "[ERRO] URL vazia."
        pause_menu
        return
    fi

    local folder_name clone_path repo_path clone_input
    folder_name="$(basename -s .git "$url")"

    echo
    read -r -p "Diretorio para clonar [Enter = $HOME]: " clone_input

    if [ -z "$clone_input" ]; then
        clone_path="$HOME"
    else
        clone_path="$(normalize_path "$clone_input")"
    fi

    if [ ! -d "$clone_path" ]; then
        echo "[ERRO] Diretorio de destino nao encontrado:"
        echo "       $clone_path"
        pause_menu
        return
    fi

    if ! prepare_clone_destination "$clone_path" "$folder_name"; then
        pause_menu
        return
    fi

    cd "$clone_path" || {
        echo "[ERRO] Nao foi possivel acessar:"
        echo "       $clone_path"
        pause_menu
        return
    }

    echo "Clonando \"$folder_name\" em: $(pwd)"

    if [ -d "$folder_name" ]; then
        if ! git clone "$url" "$folder_name"; then
            echo "[ERRO] Falha ao clonar o repositorio."
            pause_menu
            return
        fi
    elif ! git clone "$url"; then
        echo "[ERRO] Falha ao clonar o repositorio."
        pause_menu
        return
    fi

    repo_path="$(pwd)/$folder_name"

    if ! configure_repo "$repo_path"; then
        echo "[ERRO] O clone terminou, mas a configuracao local falhou."
        pause_menu
        return
    fi

    echo
    echo "[SUCESSO] Repositorio clonado e configurado."
    echo "[INFO] Local: $repo_path"
    echo "[INFO] Identidade Git: $GIT_NAME <$GIT_EMAIL>"
    echo "[INFO] core.sshCommand aponta para:"
    echo "       $CHAVE_PATH"
    echo "[INFO] Sem o pendrive, a autenticacao com esta chave deixa de funcionar."

    open_terminal "$repo_path" "$folder_name"
    pause_menu
}

use_existing_repo() {
    check_git || { pause_menu; return; }
    prepare_key || { pause_menu; return; }

    echo
    read -r -p "Cole/arraste a pasta do projeto e pressione Enter: " folder
    folder="$(normalize_path "$folder")"

    if [ ! -d "$folder" ]; then
        echo "[ERRO] Diretorio nao encontrado:"
        echo "       $folder"
        pause_menu
        return
    fi

    if ! configure_repo "$folder"; then
        pause_menu
        return
    fi

    echo
    echo "[SUCESSO] Repositorio configurado."
    echo "[INFO] user.name:  $(git -C "$folder" config --local user.name)"
    echo "[INFO] user.email: $(git -C "$folder" config --local user.email)"
    echo "[INFO] core.sshCommand:"
    echo "       $(git -C "$folder" config --local core.sshCommand)"
    echo
    echo "[INFO] O repositorio continuara apontando para a chave do pendrive."
    echo "[INFO] Ao remover o pendrive, esta autenticacao deixa de funcionar."

    open_terminal "$folder" "$(basename "$folder")"
    pause_menu
}

test_auth() {
    check_git || { pause_menu; return; }
    prepare_key || { pause_menu; return; }

    echo
    echo "[INFO] Testando autenticacao com:"
    echo "       $CHAVE_PATH"
    echo

    ssh \
        -i "$CHAVE_PATH" \
        -o IdentitiesOnly=yes \
        -o IdentityAgent=none \
        -T git@github.com

    local ssh_rc=$?

    echo
    if [ "$ssh_rc" -eq 1 ]; then
        echo "[INFO] O GitHub normalmente retorna codigo 1 mesmo quando a autenticacao SSH foi aceita."
        echo "[INFO] Confira a mensagem acima para confirmar a identidade."
    elif [ "$ssh_rc" -ne 0 ]; then
        echo "[AVISO] SSH terminou com codigo $ssh_rc."
    fi
}

menu() {
    while true; do
        echo "=========================================="
        echo "       GIT PORTATIL: WSL / UBUNTU         "
        echo "=========================================="
        echo "Raiz:       $PENDRIVE_ROOT"
        echo "Chave:      $CHAVE_PATH"
        echo "Identidade: $GIT_NAME <$GIT_EMAIL>"
        echo
        echo "1. Clonar um novo repositorio"
        echo "2. Usar um repositorio ja clonado"
        echo "3. Testar autenticacao SSH com GitHub"
        echo "4. Sair"
        echo

        read -r -p "Escolha uma opcao: " opt

        case "$opt" in
            1) clone_repo ;;
            2) use_existing_repo ;;
            3) test_auth; pause_menu ;;
            4) exit 0 ;;
            *) echo "Opcao invalida!"; echo ;;
        esac
    done
}

load_config || exit 1
prepare_key || exit 1
menu
