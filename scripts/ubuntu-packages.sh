#!/usr/bin/env bash
# ubuntu-packages.sh — Genera i file indice APT (struttura Launchpad-compatibile)
#
# Uso:
#   ./scripts/ubuntu-packages.sh [CODENAME...]
#   ./scripts/ubuntu-packages.sh              # aggiorna tutte le distro
#   ./scripts/ubuntu-packages.sh focal jammy  # aggiorna solo queste
#
# Struttura generata (identica a Launchpad):
#   ubuntu/
#     pool/main/z/zig/          ← i .deb risiedono qui
#     dists/<codename>/
#       Release
#       InRelease
#       Release.gpg
#       main/binary-amd64/
#         Packages
#         Packages.gz
#       main/binary-arm64/
#         Packages
#         Packages.gz
#
# sources.list dell'utente finale:
#   deb https://javanile.org/zig-ppa/ubuntu focal main
#
# Prerequisiti:
#   sudo apt install dpkg-dev gzip gpg

set -euo pipefail

##############################################################################
# Configurazione
##############################################################################
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="${REPO_ROOT}/ubuntu"
PRIVATE_KEY_FILE="${REPO_DIR}/private.gpg"
GPG_EMAIL="zig-ppa@javanile.org"

ORIGIN="Javanile Zig PPA"
LABEL="zig-ppa"
SUITE="stable"
COMPONENT="main"
ARCHITECTURES=("amd64" "arm64")
DESCRIPTION="Unofficial Zig compiler PPA by Javanile"

ALL_CODENAMES=("focal" "jammy" "noble")

##############################################################################
# Funzioni
##############################################################################
info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }
require_cmd() { command -v "$1" &>/dev/null || error "Comando non trovato: $1 — installa con: sudo apt install ${2:-$1}"; }

##############################################################################
# Prerequisiti
##############################################################################
require_cmd dpkg-scanpackages dpkg-dev
require_cmd gzip gzip
require_cmd gpg gpg

##############################################################################
# Distro da processare
##############################################################################
if [[ $# -gt 0 ]]; then
    CODENAMES=("$@")
else
    CODENAMES=("${ALL_CODENAMES[@]}")
fi

##############################################################################
# Importa chiave privata nel keyring (se non già presente)
##############################################################################
KEY_FP=""
KEY_FP=$(gpg --list-secret-keys --with-colons 2>/dev/null \
    | awk -F: '/^fpr:/ { print $10 }' \
    | while read -r fp; do
        uid=$(gpg --list-secret-keys --with-colons "$fp" 2>/dev/null \
              | awk -F: '/^uid:/ { print $10 }' | head -1)
        if echo "$uid" | grep -q "$GPG_EMAIL"; then echo "$fp"; fi
      done | head -1)

if [[ -z "$KEY_FP" ]]; then
    [[ -f "$PRIVATE_KEY_FILE" ]] || \
        error "Chiave privata non trovata: $PRIVATE_KEY_FILE — esegui prima: ./scripts/ubuntu-gpg-key.sh"
    info "Importo chiave privata da $PRIVATE_KEY_FILE ..."
    gpg --import "$PRIVATE_KEY_FILE"
    KEY_FP=$(gpg --list-secret-keys --with-colons "$GPG_EMAIL" 2>/dev/null \
        | awk -F: '/^fpr:/ { print $10 }' | head -1)
    [[ -n "$KEY_FP" ]] || error "Import chiave fallito."
fi
info "Chiave GPG: $KEY_FP"

##############################################################################
# Pool — i .deb risiedono in ubuntu/pool/main/z/zig/
##############################################################################
POOL_DIR="${REPO_DIR}/pool/main/z/zig"
mkdir -p "$POOL_DIR"

DEB_COUNT=$(find "$POOL_DIR" -maxdepth 1 -name "*.deb" | wc -l)
info "Pacchetti .deb nel pool: $DEB_COUNT"

##############################################################################
# Funzione: calcola checksum
##############################################################################
checksum_entry() {
    local file="$1"
    local relpath="$2"
    local size md5 sha1 sha256
    size=$(wc -c < "$file")
    md5=$(md5sum    "$file" | awk '{print $1}')
    sha1=$(sha1sum  "$file" | awk '{print $1}')
    sha256=$(sha256sum "$file" | awk '{print $1}')
    printf "md5:%s sha1:%s sha256:%s size:%s path:%s\n" \
        "$md5" "$sha1" "$sha256" "$size" "$relpath"
}

extract_field() { echo "$1" | grep -o "${2}:[^ ]*" | cut -d: -f2; }

##############################################################################
# Genera indice per ogni distro
##############################################################################
NOW=$(date -u "+%a, %d %b %Y %H:%M:%S UTC")

for CODENAME in "${CODENAMES[@]}"; do
    info "--- Processo distro: $CODENAME ---"

    DIST_DIR="${REPO_DIR}/dists/${CODENAME}"

    # Raccogli i checksum di tutti i Packages per il Release
    declare -a ALL_MD5=()
    declare -a ALL_SHA1=()
    declare -a ALL_SHA256=()

    for ARCH in "${ARCHITECTURES[@]}"; do
        BIN_DIR="${DIST_DIR}/${COMPONENT}/binary-${ARCH}"
        mkdir -p "$BIN_DIR"

        # Genera Packages filtrando per architettura (amd64 o arm64) + arch:all
        # dpkg-scanpackages scansiona il pool e produce path relativi dalla root del repo
        info "  Genero Packages per ${CODENAME}/${COMPONENT}/binary-${ARCH} ..."

        (
            cd "$REPO_DIR"
            dpkg-scanpackages --multiversion \
                --arch "$ARCH" \
                "pool/main" \
                2>/dev/null
        ) > "${BIN_DIR}/Packages" || true

        # Se l'opzione --arch non è supportata dalla versione installata, fallback senza filtro
        if [[ ! -s "${BIN_DIR}/Packages" ]]; then
            (cd "$REPO_DIR"; dpkg-scanpackages --multiversion "pool/main" 2>/dev/null) \
                > "${BIN_DIR}/Packages" || true
        fi

        gzip -9 -c "${BIN_DIR}/Packages" > "${BIN_DIR}/Packages.gz"

        PKG_REL="${COMPONENT}/binary-${ARCH}/Packages"
        PKG_GZ_REL="${COMPONENT}/binary-${ARCH}/Packages.gz"

        PKG_INFO=$(checksum_entry "${BIN_DIR}/Packages"    "$PKG_REL")
        GZ_INFO=$(checksum_entry  "${BIN_DIR}/Packages.gz" "$PKG_GZ_REL")

        ALL_MD5+=( \
            " $(extract_field "$PKG_INFO" md5)    $(extract_field "$PKG_INFO" size) $PKG_REL" \
            " $(extract_field "$GZ_INFO"  md5)    $(extract_field "$GZ_INFO"  size) $PKG_GZ_REL" \
        )
        ALL_SHA1+=( \
            " $(extract_field "$PKG_INFO" sha1)   $(extract_field "$PKG_INFO" size) $PKG_REL" \
            " $(extract_field "$GZ_INFO"  sha1)   $(extract_field "$GZ_INFO"  size) $PKG_GZ_REL" \
        )
        ALL_SHA256+=( \
            " $(extract_field "$PKG_INFO" sha256) $(extract_field "$PKG_INFO" size) $PKG_REL" \
            " $(extract_field "$GZ_INFO"  sha256) $(extract_field "$GZ_INFO"  size) $PKG_GZ_REL" \
        )

        info "  Packages (${ARCH}): $(wc -l < "${BIN_DIR}/Packages") righe"
    done

    # Genera Release
    info "  Genero ${DIST_DIR}/Release ..."
    {
        echo "Origin: $ORIGIN"
        echo "Label: $LABEL"
        echo "Suite: $SUITE"
        echo "Codename: $CODENAME"
        echo "Architectures: ${ARCHITECTURES[*]}"
        echo "Components: $COMPONENT"
        echo "Description: $DESCRIPTION"
        echo "Date: $NOW"
        echo "MD5Sum:"
        printf '%s\n' "${ALL_MD5[@]}"
        echo "SHA1:"
        printf '%s\n' "${ALL_SHA1[@]}"
        echo "SHA256:"
        printf '%s\n' "${ALL_SHA256[@]}"
    } > "${DIST_DIR}/Release"

    # Firma InRelease e Release.gpg
    info "  Firmo Release per $CODENAME ..."
    gpg --default-key "$KEY_FP" --clearsign --armor \
        --output "${DIST_DIR}/InRelease" "${DIST_DIR}/Release"

    gpg --default-key "$KEY_FP" --detach-sign --armor \
        --output "${DIST_DIR}/Release.gpg" "${DIST_DIR}/Release"

    info "  OK: $CODENAME"
done

##############################################################################
# Riepilogo
##############################################################################
echo ""
info "============================================================"
info "Repository APT aggiornato."
info ""
info "  Pool .deb : ubuntu/pool/main/z/zig/ ($DEB_COUNT pacchetti)"
info "  Distro    : ${CODENAMES[*]}"
info "  Data      : $NOW"
info ""
info "Struttura generata:"
for CODENAME in "${CODENAMES[@]}"; do
    info "  ubuntu/dists/$CODENAME/Release"
    for ARCH in "${ARCHITECTURES[@]}"; do
        info "  ubuntu/dists/$CODENAME/${COMPONENT}/binary-${ARCH}/Packages"
    done
done
info ""
info "sources.list per l'utente finale:"
for CODENAME in "${CODENAMES[@]}"; do
    info "  deb https://javanile.org/zig-ppa/ubuntu $CODENAME main"
done
info "============================================================"