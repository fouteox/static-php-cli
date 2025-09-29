#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# VÉRIFICATION DES PARAMÈTRES
# ---------------------------
if [ $# -ne 1 ]; then
    echo "Usage: $0 <version_majeure>"
    echo "Exemples: $0 8, $0 9"
    echo "Versions supportées: 8 (LTS), 9 (Innovation)"
    exit 1
fi

MAJOR_VERSION="$1"

# Validation de la version majeure
if [[ ! "$MAJOR_VERSION" =~ ^(8|9)$ ]]; then
    echo "Erreur: Version non supportée '$MAJOR_VERSION'"
    echo "Versions supportées: 8, 9"
    exit 1
fi

# ---------------------------
# CONFIGURATION MYSQL
# ---------------------------
# Workspace isolé par version majeure
WORKDIR="$HOME/fadogen-build/build-mysql-$MAJOR_VERSION"
MYSQL_REPO="https://github.com/mysql/mysql-server.git"

# Répertoires temporaires isolés par processus (évite race conditions)
STAGING_DIR="/tmp/mysql-staging-$$"
INSTALL_DIR="/tmp/mysql-install-$$"

# Nettoyage automatique en cas d'interruption
trap "rm -rf $STAGING_DIR $INSTALL_DIR" EXIT

# ---------------------------
# FONCTIONS UTILITAIRES (DRY depuis certutil-build.sh)
# ---------------------------
function check_command() {
    command -v "$1" >/dev/null 2>&1 || { echo >&2 "Erreur : $1 n'est pas installé."; exit 1; }
}

function get_latest_version() {
    local major_version="$1"
    echo "[INFO] Récupération de la dernière version MySQL $major_version.x..." >&2

    local latest_tag=$(git ls-remote --tags "$MYSQL_REPO" | \
        grep -E "mysql-${major_version}\\.[0-9]+\\.[0-9]+$" | \
        sed 's/.*refs\/tags\///' | \
        sort -V | \
        tail -1)

    if [ -z "$latest_tag" ]; then
        echo "Erreur : Aucune version trouvée pour MySQL $major_version.x" >&2
        exit 1
    fi

    echo "$latest_tag"
}

# ---------------------------
# 1. Détermination de la version (automatique ou override)
# ---------------------------
if [[ -n "${FULL_VERSION:-}" ]]; then
    # Version fournie par variable d'environnement (workflow CI)
    MYSQL_VERSION="$FULL_VERSION"
    MYSQL_BRANCH="mysql-$FULL_VERSION"
    echo "[INFO] Version fournie par FULL_VERSION: $MYSQL_VERSION"
else
    # Récupération automatique de la dernière version de la branche demandée
    MYSQL_BRANCH=$(get_latest_version "$MAJOR_VERSION")
    MYSQL_VERSION=$(echo "$MYSQL_BRANCH" | sed 's/mysql-//' | sed 's/\.[0-9]*$//')
    echo "[INFO] Version détectée automatiquement: $MYSQL_VERSION"
fi

echo "[INFO] Version sélectionnée: $MYSQL_BRANCH"
echo "[INFO] Version complète: $MYSQL_VERSION"

# ---------------------------
# 2. Vérifications préliminaires
# ---------------------------
check_command git
check_command brew

echo "[INFO] Installation des dépendances via Homebrew..."
brew install cmake ninja bison boost openssl ncurses || true

# ---------------------------
# 3. Préparer workspace isolé par version
# ---------------------------
echo "[INFO] Préparation du workspace isolé pour MySQL $MAJOR_VERSION.x..."
echo "[INFO] Workspace: $WORKDIR"

# Créer le workspace s'il n'existe pas
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Vérifier si une archive existe déjà pour cette version exacte
ARCHIVE_NAME="mysql-$MYSQL_VERSION-macos-aarch64.tar.xz"
if [ -f "$ARCHIVE_NAME" ]; then
    echo "[INFO] Archive existante trouvée: $ARCHIVE_NAME"
    echo "[INFO] Poursuite du build (écrasement de l'archive)..."
fi

# Nettoyer seulement les fichiers temporaires de build
rm -rf mysql-server
rm -rf "$STAGING_DIR"

echo "[INFO] Configuration MySQL build script"
echo "[INFO] Target: MySQL $MYSQL_VERSION for macOS ARM64"
echo "[INFO] Workspace: $WORKDIR"

echo "[INFO] Clonage de MySQL $MYSQL_VERSION..."
git clone --branch "$MYSQL_BRANCH" --depth 1 "$MYSQL_REPO" mysql-server
cd mysql-server
echo "[INFO] MySQL source clonée avec succès"

# ---------------------------
# 4. Build MySQL (ARM64 Release)
# ---------------------------
echo "[INFO] Création du répertoire de build (out-of-tree recommandé)..."
mkdir build-mysql-release
cd build-mysql-release

# Détecter la disponibilité de Boost
BOOST_OPTIONS=""
if [ -d "/opt/homebrew/opt/boost" ]; then
    echo "[INFO] Utilisation de Boost via Homebrew..."
    BOOST_OPTIONS="-DWITH_BOOST=/opt/homebrew/opt/boost -DDOWNLOAD_BOOST=0"
else
    echo "[INFO] Boost non trouvé, téléchargement automatique activé..."
    BOOST_OPTIONS="-DDOWNLOAD_BOOST=1 -DDOWNLOAD_BOOST_TIMEOUT=600"
fi

echo "[INFO] Configuration CMAKE pour macOS ARM64..."
cmake ../. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DBISON_EXECUTABLE=/opt/homebrew/opt/bison/bin/bison \
  $BOOST_OPTIONS \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl \
  -DWITH_FIDO=none \
  -DWITH_UNIT_TESTS=OFF \
  -DINSTALL_MYSQLTESTDIR=""

echo "[INFO] Compilation MySQL..."
cmake --build . --parallel

echo "[INFO] Installation temporaire..."
make install DESTDIR="$STAGING_DIR"

echo "[INFO] Build MySQL terminé avec succès"

# ---------------------------
# 5. Extraction des binaires MySQL (pattern certutil-build.sh)
# ---------------------------
MYSQLD_SRC="$STAGING_DIR/$INSTALL_DIR/bin/mysqld"
MYSQL_CLIENT_SRC="$STAGING_DIR/$INSTALL_DIR/bin/mysql"

if [ ! -f "$MYSQLD_SRC" ]; then
    echo "Erreur : mysqld non trouvé après compilation."
    exit 1
fi

if [ ! -f "$MYSQL_CLIENT_SRC" ]; then
    echo "Erreur : mysql client non trouvé après compilation."
    exit 1
fi

echo "[INFO] Création de la structure temporaire pour l'archive..."
PACKAGE_DIR="mysql-package"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

echo "[INFO] Copie COMPLÈTE de l'installation MySQL..."
cp -r "$STAGING_DIR/$INSTALL_DIR"/* "$PACKAGE_DIR/"

echo "[INFO] Vérification de la structure de l'archive..."
ls -la "$PACKAGE_DIR/"
echo "[INFO] Taille de l'installation:"
du -sh "$PACKAGE_DIR"

echo "[INFO] Déplacement vers le répertoire fadogen-build..."
cd ../..

echo "[INFO] Création de l'archive tar..."
tar -cJf "$ARCHIVE_NAME" -C "mysql-server/build-mysql-release/$PACKAGE_DIR" .

echo "[INFO] Nettoyage..."
rm -rf "mysql-server/build-mysql-release/$PACKAGE_DIR"
# Note: $STAGING_DIR et $INSTALL_DIR sont nettoyés automatiquement par le trap EXIT

# ---------------------------
# 6. Vérification
# ---------------------------
echo "[INFO] Vérification de l'archive..."
ls -la "$ARCHIVE_NAME"

echo "[SUCCESS] Archive MySQL portable créée: $(pwd)/$ARCHIVE_NAME"
echo "[INFO] Workspace préservé pour builds futurs: $WORKDIR"
echo "[INFO] Pour builder d'autres versions: ./mysql-build.sh 8|9"

# ---------------------------
# 7. Nettoyage optionnel
# ---------------------------
# echo "[INFO] Nettoyage du workspace..."
# rm -rf "$WORKDIR"