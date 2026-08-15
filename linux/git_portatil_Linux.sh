#!/usr/bin/env bash

# ============================================================
# GIT PORTATIL - LINUX
#
# Arquitetura:
#   - Este script NAO depende de Konsole, GNOME Terminal etc.
#   - Para uso grafico, utilize git_portatil_Linux.desktop.
#   - O launcher .desktop inicia o terminal com cwd em /tmp,
#     evitando que o proprio terminal prenda o pendrive.
#
# Estrutura esperada:
#   /PENDRIVE/.env
#   /PENDRIVE/id_ed25519
#   /PENDRIVE/linux/git_portatil_Linux.sh
#   /PENDRIVE/linux/git_portatil_Linux.desktop
# ============================================================

# Permite executar inclusive como:
#   sh git_portatil_Linux.sh
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -u

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
PENDRIVE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

mode_is_ssh_safe() {
    local mode="$1"

    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1

    # OpenSSH rejeita a chave quando grupo/outros possuem acesso.
    # Exemplos aceitos por este teste: 600, 400, 700.
    (( (8#$mode & 077) == 0 ))
}

parent_shell_blocks_mount() {
    local mount_target="$1"
    local parent_cwd

    parent_cwd="$(readlink -f "/proc/$PPID/cwd" 2>/dev/null || true)"

    case "${parent_cwd%/}/" in
        "${mount_target%/}/"*)
            echo
            echo "[ERRO] O processo que iniciou este script esta dentro do pendrive:"
            echo "       ${parent_cwd:-desconhecido}"
            echo
            echo "[INFO] Isso impede a desmontagem do dispositivo."
            echo
            echo "[INFO] Para uso pelo terminal, execute a partir do HOME:"
            printf '       cd ~ && bash %q\n' "$SCRIPT_PATH"
            echo
            echo "[INFO] Para uso por clique, execute:"
            echo "       git_portatil_Linux.desktop"
            return 0
            ;;
    esac

    return 1
}

# ------------------------------------------------------------
# Permissoes da chave / VFAT / exFAT
# ------------------------------------------------------------

prepare_key_permissions() {
    local current_mode mount_target mount_source fstype options
    local helper_path

    if [ ! -f "$CHAVE_PATH" ]; then
        echo "[ERRO] Chave SSH nao encontrada:"
        echo "       $CHAVE_PATH"
        return 1
    fi

    # Em filesystems Unix isto normalmente resolve diretamente.
    chmod 600 "$CHAVE_PATH" 2>/dev/null || true

    current_mode="$(stat -c '%a' "$CHAVE_PATH" 2>/dev/null || true)"
    if mode_is_ssh_safe "$current_mode"; then
        echo "[OK] Permissoes da chave SSH estao seguras ($current_mode)."
        return 0
    fi

    echo
    echo "[AVISO] A chave SSH continua com permissao ${current_mode:-desconhecida}."
    echo "[INFO] Verificando o filesystem do pendrive..."

    for cmd in findmnt mount umount stat mktemp sudo readlink; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "[ERRO] Comando necessario nao encontrado: $cmd"
            return 1
        fi
    done

    mount_target="$(findmnt -no TARGET -T "$CHAVE_PATH" 2>/dev/null || true)"
    mount_source="$(findmnt -no SOURCE -T "$CHAVE_PATH" 2>/dev/null || true)"
    fstype="$(findmnt -no FSTYPE -T "$CHAVE_PATH" 2>/dev/null || true)"
    options="$(findmnt -no OPTIONS -T "$CHAVE_PATH" 2>/dev/null || true)"

    echo "[INFO] Dispositivo: ${mount_source:-desconhecido}"
    echo "[INFO] Mountpoint:  ${mount_target:-desconhecido}"
    echo "[INFO] Filesystem:  ${fstype:-desconhecido}"

    case "$fstype" in
        vfat|fat|msdos|exfat)
            if [ -z "$mount_target" ] || [ -z "$mount_source" ]; then
                echo "[ERRO] Nao foi possivel determinar SOURCE/TARGET da montagem."
                return 1
            fi

            if parent_shell_blocks_mount "$mount_target"; then
                return 1
            fi

            echo
            echo "[INFO] $fstype nao armazena permissoes Unix por arquivo."
            echo "[INFO] O pendrive sera montado novamente com:"
            echo "       uid=$(id -u),gid=$(id -g),fmask=0177,dmask=0077"
            echo

            if ! sudo -v; then
                echo "[ERRO] Nao foi possivel validar o sudo."
                return 1
            fi

            helper_path="$(mktemp /tmp/git-portatil-mount.XXXXXX.sh)" || {
                echo "[ERRO] Nao foi possivel criar o helper temporario."
                return 1
            }

            cat > "$helper_path" <<'HELPER_EOF'
#!/usr/bin/env bash
set -u

MOUNT_SOURCE="$1"
MOUNT_TARGET="$2"
FSTYPE="$3"
USER_UID="$4"
USER_GID="$5"
ORIGINAL_SCRIPT="$6"
shift 6
SCRIPT_ARGS=("$@")

cleanup() {
    rm -f -- "$0" 2>/dev/null || true
}
trap cleanup EXIT

cd /tmp || exit 1

echo
echo "[INFO] Helper temporario iniciado fora do pendrive."
echo "[INFO] Desmontando: $MOUNT_TARGET"

if ! sudo umount "$MOUNT_TARGET"; then
    echo
    echo "[ERRO] Nao foi possivel desmontar o pendrive."
    echo "[INFO] Algum outro processo ainda esta usando o mountpoint."

    if command -v fuser >/dev/null 2>&1; then
        echo
        echo "[INFO] Processos relacionados ao mountpoint:"
        sudo fuser -vm "$MOUNT_TARGET" 2>/dev/null || true
    fi

    echo
    echo "[INFO] Feche os processos indicados e execute novamente."
    exit 1
fi

if ! sudo mkdir -p "$MOUNT_TARGET"; then
    echo "[ERRO] Nao foi possivel recriar o mountpoint:"
    echo "       $MOUNT_TARGET"
    exit 1
fi

echo "[INFO] Montando novamente com permissoes restritas..."

if ! sudo mount -t "$FSTYPE" \
    -o "uid=${USER_UID},gid=${USER_GID},fmask=0177,dmask=0077" \
    "$MOUNT_SOURCE" "$MOUNT_TARGET"; then
    echo "[ERRO] Falha ao montar novamente o pendrive."
    exit 1
fi

echo "[OK] Pendrive montado novamente."

if command -v findmnt >/dev/null 2>&1; then
    echo "[INFO] Opcoes atuais:"
    findmnt -no OPTIONS -T "$MOUNT_TARGET" 2>/dev/null || true
fi

if [ ! -f "$ORIGINAL_SCRIPT" ]; then
    echo "[ERRO] Script original nao encontrado apos a nova montagem:"
    echo "       $ORIGINAL_SCRIPT"
    exit 1
fi

echo "[INFO] Relancando o script original..."
echo

trap - EXIT
rm -f -- "$0" 2>/dev/null || true
exec bash "$ORIGINAL_SCRIPT" "${SCRIPT_ARGS[@]}"
HELPER_EOF

            chmod 700 "$helper_path" || {
                rm -f "$helper_path"
                echo "[ERRO] Nao foi possivel preparar o helper temporario."
                return 1
            }

            # O helper esta em /tmp e o processo atual deve estar fora do USB.
            exec bash "$helper_path" \
                "$mount_source" \
                "$mount_target" \
                "$fstype" \
                "$(id -u)" \
                "$(id -g)" \
                "$SCRIPT_PATH" \
                "$@"
            ;;
        *)
            echo "[ERRO] Nao foi possivel garantir permissoes seguras para a chave."
            echo "[INFO] Filesystem detectado: ${fstype:-desconhecido}"
            echo "[INFO] Opcoes de montagem: ${options:-desconhecidas}"
            return 1
            ;;
    esac
}

# ------------------------------------------------------------
# Git
# ------------------------------------------------------------

check_git() {
    echo "[INFO] Verificando Git..."

    if command -v git >/dev/null 2>&1; then
        echo "[OK] Git operacional."
        return 0
    fi

    echo "[AVISO] Git nao localizado. Tentando instalar..."

    if [ -f /etc/arch-release ]; then
        sudo pacman -Sy --noconfirm git
    elif [ -f /etc/debian_version ]; then
        sudo apt update && sudo apt install -y git
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y git
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper --non-interactive install git
    else
        echo "[ERRO] Nao foi possivel detectar um gerenciador suportado."
        return 1
    fi
}

configure_repo() {
    git config core.sshCommand "ssh -i '${CHAVE_PATH}' -o IdentitiesOnly=yes"
    git config --local user.name "$GIT_NAME"
    git config --local user.email "$GIT_EMAIL"
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

    echo
    read -r -p "URL SSH (git@github.com:usuario/projeto.git): " url

    if [ -z "$url" ]; then
        echo "[ERRO] URL vazia."
        return
    fi

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
    configure_repo

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

    if [ ! -d "$folder/.git" ]; then
        echo "[ERRO] Repositorio Git nao encontrado:"
        echo "       $folder"
        return
    fi

    cd "$folder" || return
    configure_repo

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
