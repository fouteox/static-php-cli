#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# VÉRIFICATION DES PARAMÈTRES
# ---------------------------
if [ $# -ne 1 ]; then
    echo "Usage: $0 <version_majeure>"
    echo "Exemples: $0 14, $0 15, $0 16, $0 17"
    echo "Versions supportées: 14, 15, 16, 17"
    exit 1
fi

MAJOR_VERSION="$1"

# Validation de la version majeure
if [[ ! "$MAJOR_VERSION" =~ ^(14|15|16|17)$ ]]; then
    echo "Erreur: Version non supportée '$MAJOR_VERSION'"
    echo "Versions supportées: 14, 15, 16, 17"
    exit 1
fi

# ---------------------------
# CONFIGURATION POSTGRESQL
# ---------------------------
# Workspace isolé par version majeure
WORKDIR="$HOME/fadogen-build/build-postgresql-$MAJOR_VERSION"
POSTGRESQL_REPO="https://github.com/postgres/postgres.git"

# Répertoires temporaires isolés par processus (évite race conditions)
STAGING_DIR="/tmp/postgresql-staging-$$"
INSTALL_DIR="/tmp/postgresql-install-$$"

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
    echo "[INFO] Récupération de la dernière version PostgreSQL $major_version.x..." >&2

    local latest_tag=$(git ls-remote --tags "$POSTGRESQL_REPO" | \
        grep -E "REL_${major_version}_[0-9]+$" | \
        sed 's/.*refs\/tags\///' | \
        sort -V | \
        tail -1)

    if [ -z "$latest_tag" ]; then
        echo "Erreur : Aucune version trouvée pour PostgreSQL $major_version.x" >&2
        exit 1
    fi

    echo "$latest_tag"
}

# ---------------------------
# 1. Détermination de la version (automatique ou override)
# ---------------------------
if [[ -n "${FULL_VERSION:-}" ]]; then
    # Version fournie par variable d'environnement (workflow CI)
    POSTGRESQL_VERSION="$FULL_VERSION"
    # Convertir version X.Y en tag REL_X_Y
    POSTGRESQL_BRANCH="REL_$(echo $FULL_VERSION | tr '.' '_')"
    echo "[INFO] Version fournie par FULL_VERSION: $POSTGRESQL_VERSION"
else
    # Récupération automatique de la dernière version de la branche demandée
    POSTGRESQL_BRANCH=$(get_latest_version "$MAJOR_VERSION")
    POSTGRESQL_VERSION=$(echo "$POSTGRESQL_BRANCH" | sed 's/REL_//' | sed 's/_[0-9]*$//' | tr '_' '.')
    echo "[INFO] Version détectée automatiquement: $POSTGRESQL_VERSION"
fi

echo "[INFO] Version sélectionnée: $POSTGRESQL_BRANCH"
echo "[INFO] Version complète: $POSTGRESQL_VERSION"

# ---------------------------
# 2. Vérifications préliminaires
# ---------------------------
check_command git
check_command brew

echo "[INFO] Installation des dépendances via Homebrew..."
brew install pkgconf readline openssl icu4c || true

# ---------------------------
# 3. Préparer workspace isolé par version
# ---------------------------
echo "[INFO] Préparation du workspace isolé pour PostgreSQL $MAJOR_VERSION.x..."
echo "[INFO] Workspace: $WORKDIR"

# Créer le workspace s'il n'existe pas
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Vérifier si une archive existe déjà pour cette version exacte
ARCHIVE_NAME="postgresql-$POSTGRESQL_VERSION-macos-aarch64.tar.xz"
if [ -f "$ARCHIVE_NAME" ]; then
    echo "[INFO] Archive existante trouvée: $ARCHIVE_NAME"
    echo "[INFO] Poursuite du build (écrasement de l'archive)..."
fi

# Nettoyer seulement les fichiers temporaires de build
rm -rf postgres
rm -rf "$STAGING_DIR"

echo "[INFO] Configuration PostgreSQL build script"
echo "[INFO] Target: PostgreSQL $POSTGRESQL_VERSION for macOS ARM64"
echo "[INFO] Workspace: $WORKDIR"

echo "[INFO] Clonage de PostgreSQL $POSTGRESQL_VERSION..."
git clone --branch "$POSTGRESQL_BRANCH" --depth 1 "$POSTGRESQL_REPO" postgres
cd postgres
echo "[INFO] PostgreSQL source clonée avec succès"

# ---------------------------
# 4. Build PostgreSQL (ARM64 Release)
# ---------------------------
echo "[INFO] Configuration PostgreSQL pour macOS ARM64..."

# Configuration avec ./configure (standard PostgreSQL)
# Utiliser le chemin final d'installation pour éviter les chemins temporaires hardcodés
FINAL_PREFIX="/Users/Shared/Fadogen/services/postgresql/$MAJOR_VERSION"
./configure \
  --prefix="$FINAL_PREFIX" \
  --with-openssl \
  --with-icu \
  CFLAGS="-O2 -arch arm64" \
  LDFLAGS="-L/opt/homebrew/opt/openssl/lib" \
  CPPFLAGS="-I/opt/homebrew/opt/openssl/include" \
  PKG_CONFIG_PATH="/opt/homebrew/opt/icu4c/lib/pkgconfig"

echo "[INFO] Compilation PostgreSQL..."
make -j

echo "[INFO] Installation temporaire..."
make install DESTDIR="$STAGING_DIR"

echo "[INFO] Build PostgreSQL terminé avec succès"

# ---------------------------
# 5. Extraction des binaires PostgreSQL (pattern certutil-build.sh)
# ---------------------------
POSTGRES_SRC="$STAGING_DIR/$FINAL_PREFIX/bin/postgres"
PSQL_CLIENT_SRC="$STAGING_DIR/$FINAL_PREFIX/bin/psql"

if [ ! -f "$POSTGRES_SRC" ]; then
    echo "Erreur : postgres non trouvé après compilation."
    exit 1
fi

if [ ! -f "$PSQL_CLIENT_SRC" ]; then
    echo "Erreur : psql client non trouvé après compilation."
    exit 1
fi

echo "[INFO] Création de la structure temporaire pour l'archive..."
PACKAGE_DIR="postgresql-package"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

echo "[INFO] Copie COMPLÈTE de l'installation PostgreSQL..."
cp -r "$STAGING_DIR/$FINAL_PREFIX"/* "$PACKAGE_DIR/"

echo "[INFO] Vérification de la structure de l'archive..."
ls -la "$PACKAGE_DIR/"
echo "[INFO] Taille de l'installation:"
du -sh "$PACKAGE_DIR"

echo "[INFO] Déplacement vers le répertoire fadogen-build..."
cd ..

echo "[INFO] Création de l'archive tar..."
tar -cJf "$ARCHIVE_NAME" -C "postgres/$PACKAGE_DIR" .

echo "[INFO] Nettoyage..."
rm -rf "postgres/$PACKAGE_DIR"
# Note: $STAGING_DIR et $INSTALL_DIR sont nettoyés automatiquement par le trap EXIT

# ---------------------------
# 6. Vérification
# ---------------------------
echo "[INFO] Vérification de l'archive..."
ls -la "$ARCHIVE_NAME"

echo "[SUCCESS] Archive PostgreSQL portable créée: $(pwd)/$ARCHIVE_NAME"
echo "[INFO] Workspace préservé pour builds futurs: $WORKDIR"
echo "[INFO] Pour builder d'autres versions: ./postgresql-build.sh 14|15|16|17"

# ---------------------------
# 7. Nettoyage optionnel
# ---------------------------
# echo "[INFO] Nettoyage du workspace..."
# rm -rf "$WORKDIR"