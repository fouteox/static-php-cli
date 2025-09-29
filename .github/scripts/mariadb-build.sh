#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# VÉRIFICATION DES PARAMÈTRES
# ---------------------------
if [ $# -ne 1 ]; then
    echo "Usage: $0 <version_majeure>"
    echo "Exemples: $0 10, $0 11, $0 12"
    echo "Versions supportées: 10 (LTS), 11 (LTS), 12 (Rolling)"
    exit 1
fi

MAJOR_VERSION="$1"

# Validation de la version majeure
if [[ ! "$MAJOR_VERSION" =~ ^(10|11|12)$ ]]; then
    echo "Erreur: Version non supportée '$MAJOR_VERSION'"
    echo "Versions supportées: 10, 11, 12"
    exit 1
fi

# ---------------------------
# CONFIGURATION MARIADB
# ---------------------------
# Workspace isolé par version majeure
WORKDIR="$HOME/fadogen-build/build-mariadb-$MAJOR_VERSION"
MARIADB_REPO="https://github.com/MariaDB/server.git"

# Répertoires temporaires isolés par processus (évite race conditions)
STAGING_DIR="/tmp/mariadb-staging-$$"
INSTALL_DIR="/tmp/mariadb-install-$$"

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
    echo "[INFO] Récupération de la dernière version MariaDB $major_version.x..." >&2

    local latest_tag=$(git ls-remote --tags "$MARIADB_REPO" | \
        grep -E "mariadb-${major_version}\.[0-9]+\.[0-9]+$" | \
        sed 's/.*refs\/tags\///' | \
        sort -V | \
        tail -1)

    if [ -z "$latest_tag" ]; then
        echo "Erreur : Aucune version trouvée pour MariaDB $major_version.x" >&2
        exit 1
    fi

    echo "$latest_tag"
}

# ---------------------------
# 1. Détermination de la version (automatique ou override)
# ---------------------------
if [[ -n "${FULL_VERSION:-}" ]]; then
    # Version fournie par variable d'environnement (workflow CI)
    MARIADB_VERSION="$FULL_VERSION"
    MARIADB_BRANCH="mariadb-$FULL_VERSION"
    echo "[INFO] Version fournie par FULL_VERSION: $MARIADB_VERSION"
else
    # Récupération automatique de la dernière version de la branche demandée
    MARIADB_BRANCH=$(get_latest_version "$MAJOR_VERSION")
    MARIADB_VERSION=$(echo "$MARIADB_BRANCH" | sed 's/mariadb-//' | sed 's/\.[0-9]*$//')
    echo "[INFO] Version détectée automatiquement: $MARIADB_VERSION"
fi

echo "[INFO] Version sélectionnée: $MARIADB_BRANCH"
echo "[INFO] Version complète: $MARIADB_VERSION"

# ---------------------------
# 2. Vérifications préliminaires
# ---------------------------
check_command git
check_command brew

echo "[INFO] Installation des dépendances via Homebrew..."
brew install cmake ninja bison || true

# ---------------------------
# 3. Préparer workspace isolé par version
# ---------------------------
echo "[INFO] Préparation du workspace isolé pour MariaDB $MAJOR_VERSION.x..."
echo "[INFO] Workspace: $WORKDIR"

# Créer le workspace s'il n'existe pas
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Vérifier si une archive existe déjà pour cette version exacte
ARCHIVE_NAME="mariadb-$MARIADB_VERSION-macos-aarch64.tar.xz"
if [ -f "$ARCHIVE_NAME" ]; then
    echo "[INFO] Archive existante trouvée: $ARCHIVE_NAME"
    echo "[INFO] Poursuite du build (écrasement de l'archive)..."
fi

# Nettoyer seulement les fichiers temporaires de build
rm -rf server
rm -rf "$STAGING_DIR"

echo "[INFO] Configuration MariaDB build script"
echo "[INFO] Target: MariaDB $MARIADB_VERSION for macOS ARM64"
echo "[INFO] Workspace: $WORKDIR"

echo "[INFO] Clonage de MariaDB $MARIADB_VERSION..."
git clone --branch "$MARIADB_BRANCH" --depth 1 "$MARIADB_REPO" server
cd server
echo "[INFO] MariaDB source clonée avec succès"

# ---------------------------
# 4. Build MariaDB (ARM64 Release)
# ---------------------------
echo "[INFO] Création du répertoire de build (out-of-tree recommandé)..."
mkdir build-mariadb-release
cd build-mariadb-release

echo "[INFO] Configuration CMAKE pour macOS ARM64..."
cmake ../. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DBISON_EXECUTABLE=/opt/homebrew/opt/bison/bin/bison \
  -DWITH_EMBEDDED_SERVER=OFF \
  -DPLUGIN_MROONGA=NO \
  -DPLUGIN_SPIDER=NO \
  -DPLUGIN_OQGRAPH=NO \
  -DPLUGIN_ROCKSDB=NO \
  -DWITHOUT_DYNAMIC_PLUGINS=ON

echo "[INFO] Compilation MariaDB..."
cmake --build . --parallel

echo "[INFO] Installation temporaire..."
make install DESTDIR="$STAGING_DIR"

echo "[INFO] Build MariaDB terminé avec succès"

# ---------------------------
# 5. Extraction des binaires MariaDB (pattern certutil-build.sh)
# ---------------------------
MARIADBD_SRC="$STAGING_DIR/$INSTALL_DIR/bin/mariadbd"
MARIADB_CLIENT_SRC="$STAGING_DIR/$INSTALL_DIR/bin/mariadb"

if [ ! -f "$MARIADBD_SRC" ]; then
    echo "Erreur : mariadbd non trouvé après compilation."
    exit 1
fi

if [ ! -f "$MARIADB_CLIENT_SRC" ]; then
    echo "Erreur : mariadb client non trouvé après compilation."
    exit 1
fi

echo "[INFO] Création de la structure temporaire pour l'archive..."
PACKAGE_DIR="mariadb-package"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

echo "[INFO] Copie COMPLÈTE de l'installation MariaDB..."
cp -r "$STAGING_DIR/$INSTALL_DIR"/* "$PACKAGE_DIR/"

echo "[INFO] Vérification de la structure de l'archive..."
ls -la "$PACKAGE_DIR/"
echo "[INFO] Taille de l'installation:"
du -sh "$PACKAGE_DIR"

echo "[INFO] Déplacement vers le répertoire fadogen-build..."
cd ../..

echo "[INFO] Création de l'archive tar..."
tar -cJf "$ARCHIVE_NAME" -C "server/build-mariadb-release/$PACKAGE_DIR" .

echo "[INFO] Nettoyage..."
rm -rf "server/build-mariadb-release/$PACKAGE_DIR"
# Note: $STAGING_DIR et $INSTALL_DIR sont nettoyés automatiquement par le trap EXIT

# ---------------------------
# 6. Vérification
# ---------------------------
echo "[INFO] Vérification de l'archive..."
ls -la "$ARCHIVE_NAME"

echo "[SUCCESS] Archive MariaDB portable créée: $(pwd)/$ARCHIVE_NAME"
echo "[INFO] Workspace préservé pour builds futurs: $WORKDIR"
echo "[INFO] Pour builder d'autres versions: ./mariadb-build.sh 10|11|12"

# ---------------------------
# 7. Nettoyage optionnel
# ---------------------------
# echo "[INFO] Nettoyage du workspace..."
# rm -rf "$WORKDIR"