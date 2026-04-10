#!/usr/bin/env bash
# ubuntu-packages.sh — Genera i file indice APT per il PPA zig-ppa@javanile.org
#
# Uso:
#   ./scripts/ubuntu-packages.sh
#
# Prerequisiti:
#   - dpkg-dev      (per dpkg-scanpackages)
#   - apt-utils     (per apt-ftparchive)
#   - gzip
#   - gpg           (con chiave privata ubuntu/private.gpg già importata)
#
# Genera in ubuntu/:
#   Packages        — indice dei pacchetti .deb
#   Packages.gz     — versione compressa
#   Release         — metadati del repository
#   InRelease       — Release firmato inline (GPG clearsign)
#   Release.gpg     — firma detached

set -euo pipefail

##############################################################################
# Configurazione
##############################################################################
REPO_DIR="ubuntu"
PRIVATE_KEY_FILE="ubuntu/private.gpg"
GPG_EMAIL="zig-ppa@javanile.org"

ORIGIN="Javanile Zig PPA"
LABEL="zig-ppa"
CODENAME="focal"
SUITE="stable"
COMPONENT="main"
ARCHITECTURES="amd64 arm64"
DESCRIPTION="Unofficial Zig compiler PPA by Javanile"

##############################################################################
# Funzioni di supporto
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
    if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
        error "Chiave privata non trovata: $PRIVATE_KEY_FILE"$'\n'"Esegui prima: ./scripts/ubuntu-gpg-key.sh"
    fi
    info "Importo chiave privata da $PRIVATE_KEY_FILE ..."
    gpg --import "$PRIVATE_KEY_FILE"
    KEY_FP=$(gpg --list-secret-keys --with-colons "$GPG_EMAIL" 2>/dev/null \
        | awk -F: '/^fpr:/ { print $10 }' | head -1)
    [[ -n "$KEY_FP" ]] || error "Import chiave fallito."
fi
info "Chiave GPG: $KEY_FP"

##############################################################################
# Genera Packages e Packages.gz
##############################################################################
info "Scansiono i file .deb in $REPO_DIR/ ..."

# dpkg-scanpackages vuole essere eseguito dalla root del repo
# e il path relativo alla dir dei .deb
DEB_COUNT=$(find "$REPO_DIR" -maxdepth 1 -name "*.deb" | wc -l)
if [[ "$DEB_COUNT" -eq 0 ]]; then
    info "Nessun .deb trovato in $REPO_DIR/ — genero Packages vuoto."
fi

dpkg-scanpackages --multiversion "$REPO_DIR" /dev/null > "$REPO_DIR/Packages" 2>/dev/null || \
    dpkg-scanpackages "$REPO_DIR" > "$REPO_DIR/Packages"

gzip -9 -c "$REPO_DIR/Packages" > "$REPO_DIR/Packages.gz"

info "Packages: $(wc -l < "$REPO_DIR/Packages") righe"

##############################################################################
# Calcola checksum dei file indice
##############################################################################
compute_checksums() {
    local file="$1"
    local relpath
    relpath=$(basename "$file")
    local size
    size=$(wc -c < "$file")
    local md5 sha1 sha256
    md5=$(md5sum "$file" | awk '{print $1}')
    sha1=$(sha1sum "$file" | awk '{print $1}')
    sha256=$(sha256sum "$file" | awk '{print $1}')
    echo "md5:$md5 sha1:$sha1 sha256:$sha256 size:$size name:$relpath"
}

PKG_INFO=$(compute_checksums "$REPO_DIR/Packages")
PKG_GZ_INFO=$(compute_checksums "$REPO_DIR/Packages.gz")

extract() { echo "$1" | grep -o "${2}:[^ ]*" | cut -d: -f2; }

##############################################################################
# Genera Release
##############################################################################
info "Genero $REPO_DIR/Release ..."

NOW=$(date -u "+%a, %d %b %Y %H:%M:%S UTC")

cat > "$REPO_DIR/Release" <<EOF
Origin: $ORIGIN
Label: $LABEL
Suite: $SUITE
Codename: $CODENAME
Version: 1.0
Architectures: $ARCHITECTURES
Components: $COMPONENT
Description: $DESCRIPTION
Date: $NOW
MD5Sum:
 $(extract "$PKG_INFO" md5) $(extract "$PKG_INFO" size) Packages
 $(extract "$PKG_GZ_INFO" md5) $(extract "$PKG_GZ_INFO" size) Packages.gz
SHA1:
 $(extract "$PKG_INFO" sha1) $(extract "$PKG_INFO" size) Packages
 $(extract "$PKG_GZ_INFO" sha1) $(extract "$PKG_GZ_INFO" size) Packages.gz
SHA256:
 $(extract "$PKG_INFO" sha256) $(extract "$PKG_INFO" size) Packages
 $(extract "$PKG_GZ_INFO" sha256) $(extract "$PKG_GZ_INFO" size) Packages.gz
EOF

##############################################################################
# Firma: InRelease (clearsign) e Release.gpg (detached)
##############################################################################
info "Firmo con GPG (key: $KEY_FP) ..."

gpg --default-key "$KEY_FP" \
    --clearsign \
    --armor \
    --output "$REPO_DIR/InRelease" \
    "$REPO_DIR/Release"

gpg --default-key "$KEY_FP" \
    --detach-sign \
    --armor \
    --output "$REPO_DIR/Release.gpg" \
    "$REPO_DIR/Release"

##############################################################################
# Riepilogo
##############################################################################
echo ""
info "============================================================"
info "Indice APT aggiornato in $REPO_DIR/:"
for f in Packages Packages.gz Release InRelease Release.gpg; do
    size=$(wc -c < "$REPO_DIR/$f")
    info "  $f ($size bytes)"
done
info ""
info "Pacchetti .deb indicizzati: $DEB_COUNT"
info "Data release: $NOW"
info "============================================================"