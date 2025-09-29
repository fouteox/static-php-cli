#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# VÉRIFICATION DES PARAMÈTRES
# ---------------------------
if [ $# -ne 1 ]; then
    echo "Usage: $0 <version_majeure>"
    echo "Exemples: $0 7, $0 8"
    echo "Versions supportées: 7 (LTS), 8 (GA)"
    exit 1
fi

MAJOR_VERSION="$1"

# Source la configuration centralisée
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/services-config.sh"

# Validation dynamique de la version majeure
SUPPORTED_VERSIONS=$(get_supported_versions "redis")
if ! is_version_supported "redis" "$MAJOR_VERSION"; then
    echo "Erreur: Version non supportée '$MAJOR_VERSION'"
    echo "Versions supportées: $SUPPORTED_VERSIONS"
    exit 1
fi

# ---------------------------
# CONFIGURATION REDIS
# ---------------------------
# Workspace isolé par version majeure
WORKDIR="$HOME/fadogen-build/build-redis-$MAJOR_VERSION"
REDIS_REPO="https://github.com/redis/redis.git"

# Répertoires temporaires isolés par processus (évite race conditions)
STAGING_DIR="/tmp/redis-staging-$$"
INSTALL_DIR="/tmp/redis-install-$$"

# Nettoyage automatique en cas d'interruption
trap 'rm -rf "$STAGING_DIR" "$INSTALL_DIR"' EXIT

# ---------------------------
# FONCTIONS UTILITAIRES (DRY depuis certutil-build.sh)
# ---------------------------
function check_command() {
    command -v "$1" >/dev/null 2>&1 || { echo >&2 "Erreur : $1 n'est pas installé."; exit 1; }
}

function get_latest_version() {
    local major_version="$1"
    echo "[INFO] Récupération de la dernière version Redis $major_version.x..." >&2

    local latest_tag
    latest_tag=$(git ls-remote --tags "$REDIS_REPO" | \
        grep -E "${major_version}\\.[0-9]+\\.[0-9]+$" | \
        sed 's/.*refs\/tags\///' | \
        sort -V | \
        tail -1)

    if [ -z "$latest_tag" ]; then
        echo "Erreur : Aucune version trouvée pour Redis $major_version.x" >&2
        exit 1
    fi

    echo "$latest_tag"
}

# ---------------------------
# 1. Détermination de la version (automatique ou override)
# ---------------------------
if [[ -n "${FULL_VERSION:-}" ]]; then
    # Version fournie par variable d'environnement (workflow CI)
    REDIS_VERSION="$FULL_VERSION"
    REDIS_BRANCH="$FULL_VERSION"
    echo "[INFO] Version fournie par FULL_VERSION: $REDIS_VERSION"
else
    # Récupération automatique de la dernière version de la branche demandée
    REDIS_BRANCH=$(get_latest_version "$MAJOR_VERSION")
    REDIS_VERSION="${REDIS_BRANCH%.*}"
    echo "[INFO] Version détectée automatiquement: $REDIS_VERSION"
fi

echo "[INFO] Version sélectionnée: $REDIS_BRANCH"
echo "[INFO] Version complète: $REDIS_VERSION"

# ---------------------------
# 2. Vérifications préliminaires
# ---------------------------
check_command git
check_command brew

echo "[INFO] Installation des dépendances via Homebrew..."
brew install coreutils make openssl llvm@18 cmake gnu-sed automake libtool wget || true

# Installation de Rust via Homebrew
echo "[INFO] Installation de Rust via Homebrew..."
brew install rust || true

# ---------------------------
# 3. Préparer workspace isolé par version
# ---------------------------
echo "[INFO] Préparation du workspace isolé pour Redis $MAJOR_VERSION.x..."
echo "[INFO] Workspace: $WORKDIR"

# Créer le workspace s'il n'existe pas
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Vérifier si une archive existe déjà pour cette version exacte
ARCHIVE_NAME="redis-$REDIS_VERSION-macos-aarch64.tar.xz"
if [ -f "$ARCHIVE_NAME" ]; then
    echo "[INFO] Archive existante trouvée: $ARCHIVE_NAME"
    echo "[INFO] Poursuite du build (écrasement de l'archive)..."
fi

# Nettoyer seulement les fichiers temporaires de build
rm -rf redis
rm -rf "$STAGING_DIR"

echo "[INFO] Configuration Redis build script"
echo "[INFO] Target: Redis $REDIS_VERSION for macOS ARM64"
echo "[INFO] Workspace: $WORKDIR"

echo "[INFO] Clonage de Redis $REDIS_VERSION..."
git clone --branch "$REDIS_BRANCH" --depth 1 "$REDIS_REPO" redis
cd redis
echo "[INFO] Redis source clonée avec succès"

# ---------------------------
# 4. Build Redis (ARM64 Release)
# ---------------------------
echo "[INFO] Configuration des variables d'environnement pour macOS ARM64..."

# Configuration spécifique macOS d'après la doc officielle
HOMEBREW_PREFIX="$(brew --prefix)"
export HOMEBREW_PREFIX
export BUILD_WITH_MODULES=yes
export BUILD_TLS=yes
export DISABLE_WERRORS=yes

# PATH complexe avec tous les outils GNU
export PATH="$HOMEBREW_PREFIX/opt/libtool/libexec/gnubin:$HOMEBREW_PREFIX/opt/llvm@18/bin:$HOMEBREW_PREFIX/opt/make/libexec/gnubin:$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin:$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin:$PATH"
export LDFLAGS="-L$HOMEBREW_PREFIX/opt/llvm@18/lib"
export CPPFLAGS="-I$HOMEBREW_PREFIX/opt/llvm@18/include"

echo "[INFO] Variables d'environnement configurées:"
echo "[INFO] HOMEBREW_PREFIX=$HOMEBREW_PREFIX"
echo "[INFO] BUILD_WITH_MODULES=$BUILD_WITH_MODULES"
echo "[INFO] BUILD_TLS=$BUILD_TLS"

# Création du répertoire de build
BUILD_DIR="$WORKDIR/redis/build_dir"
mkdir -p "$BUILD_DIR/etc"

echo "[INFO] Compilation Redis..."
# Build dans le sous-répertoire comme spécifié dans la doc officielle
make -j "$(nproc)" all OS=macos

echo "[INFO] Installation temporaire..."
make install PREFIX="$BUILD_DIR" OS=macos

echo "[INFO] Build Redis terminé avec succès"

# ---------------------------
# 5. Extraction des binaires Redis (pattern certutil-build.sh)
# ---------------------------
REDIS_SERVER_SRC="$BUILD_DIR/bin/redis-server"
REDIS_CLI_SRC="$BUILD_DIR/bin/redis-cli"

if [ ! -f "$REDIS_SERVER_SRC" ]; then
    echo "Erreur : redis-server non trouvé après compilation."
    exit 1
fi

if [ ! -f "$REDIS_CLI_SRC" ]; then
    echo "Erreur : redis-cli non trouvé après compilation."
    exit 1
fi

echo "[INFO] Création de la structure temporaire pour l'archive..."
PACKAGE_DIR="redis-package"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

echo "[INFO] Copie COMPLÈTE de l'installation Redis..."
cp -r "$BUILD_DIR"/* "$PACKAGE_DIR/"

echo "[INFO] Vérification de la structure de l'archive..."
ls -la "$PACKAGE_DIR/"
echo "[INFO] Taille de l'installation:"
du -sh "$PACKAGE_DIR"

echo "[INFO] Déplacement vers le répertoire fadogen-build..."
cd ..

echo "[INFO] Création de l'archive tar..."
tar -cJf "$ARCHIVE_NAME" -C "redis/$PACKAGE_DIR" .

echo "[INFO] Nettoyage..."
rm -rf "redis/$PACKAGE_DIR"
# Note: $STAGING_DIR et $INSTALL_DIR sont nettoyés automatiquement par le trap EXIT

# ---------------------------
# 6. Vérification
# ---------------------------
echo "[INFO] Vérification de l'archive..."
ls -la "$ARCHIVE_NAME"

echo "[SUCCESS] Archive Redis portable créée: $(pwd)/$ARCHIVE_NAME"
echo "[INFO] Workspace préservé pour builds futurs: $WORKDIR"
echo "[INFO] Pour builder d'autres versions: ./redis-build.sh 7|8"

# ---------------------------
# 7. Nettoyage optionnel
# ---------------------------
# echo "[INFO] Nettoyage du workspace..."
# rm -rf "$WORKDIR"