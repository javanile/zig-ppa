#!/usr/bin/env bash
# build-deb.sh — Scarica il tarball Zig ufficiale e genera il pacchetto .deb
#
# Uso:
#   ./scripts/build-deb.sh <VERSION>
#   ./scripts/build-deb.sh 0.13.0
#
# Prerequisiti:
#   sudo apt install debhelper dpkg-dev devscripts curl jq xz-utils
#
# Output:
#   ubuntu/pool/main/z/zig/zig_VERSION-1_amd64.deb

set -euo pipefail

##############################################################################
# Argomenti
##############################################################################
ZIG_VERSION="${1:-}"
if [[ -z "$ZIG_VERSION" ]]; then
    echo "Uso: $0 <VERSION>   es. $0 0.13.0" >&2
    exit 1
fi

##############################################################################
# Configurazione
##############################################################################
ARCH="x86_64"
TARBALL_NAME="zig-linux-${ARCH}-${ZIG_VERSION}.tar.xz"
TARBALL_URL="https://ziglang.org/download/${ZIG_VERSION}/${TARBALL_NAME}"
INDEX_URL="https://ziglang.org/download/index.json"

MAINTAINER="Francesco Bianco <francescobianco@javanile.org>"
DEB_REVISION="1"
PKG_NAME="zig"
PKG_VERSION="${ZIG_VERSION}-${DEB_REVISION}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEBIAN_TEMPLATE="${REPO_ROOT}/debian"
BUILD_DIR="${REPO_ROOT}/build/zig-${ZIG_VERSION}"
ORIG_TARBALL="${REPO_ROOT}/build/${PKG_NAME}_${ZIG_VERSION}.orig.tar.xz"
OUTPUT_DIR="${REPO_ROOT}/ubuntu/pool/main/z/zig"

##############################################################################
# Funzioni
##############################################################################
info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() {
    command -v "$1" &>/dev/null || error "Comando non trovato: $1 — installa con: sudo apt install ${2:-$1}"
}

# Copia un file da debian/ sostituendo i placeholder
install_template() {
    local src="${DEBIAN_TEMPLATE}/$1"
    local dst="${BUILD_DIR}/debian/$1"
    mkdir -p "$(dirname "$dst")"
    sed \
        -e "s|@ZIG_VERSION@|${ZIG_VERSION}|g" \
        -e "s|@MAINTAINER@|${MAINTAINER}|g" \
        -e "s|@DATE@|${BUILD_DATE}|g" \
        -e "s|@TARBALL_URL@|${TARBALL_URL}|g" \
        "$src" > "$dst"
}

# Copia un file statico da debian/ senza modifiche
install_static() {
    local src="${DEBIAN_TEMPLATE}/$1"
    local dst="${BUILD_DIR}/debian/$1"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
}

##############################################################################
# Prerequisiti
##############################################################################
require_cmd curl curl
require_cmd jq jq
require_cmd sha256sum coreutils
require_cmd dpkg-buildpackage dpkg-dev
require_cmd dh debhelper

[[ -d "$DEBIAN_TEMPLATE" ]] || \
    error "Directory debian/ non trovata in $REPO_ROOT — assicurati di eseguire lo script dalla root del repo."

##############################################################################
# Step 3 — Scarica il tarball ufficiale
##############################################################################
mkdir -p "${REPO_ROOT}/build"

TARBALL_CACHE="${REPO_ROOT}/build/${TARBALL_NAME}"

if [[ -f "$TARBALL_CACHE" ]]; then
    info "Tarball già presente in cache: $TARBALL_CACHE"
else
    info "Scarico $TARBALL_URL ..."
    curl --fail --location --progress-bar \
        --output "$TARBALL_CACHE" \
        "$TARBALL_URL"
fi

##############################################################################
# Step 4 — Verifica checksum SHA256
##############################################################################
info "Recupero checksum atteso da $INDEX_URL ..."

EXPECTED_SHA256=$(curl --fail --silent "$INDEX_URL" \
    | jq -r --arg ver "$ZIG_VERSION" --arg arch "${ARCH}-linux" \
        '.[$ver][$arch].shasum // empty')

if [[ -z "$EXPECTED_SHA256" ]]; then
    error "Versione '$ZIG_VERSION' o architettura '${ARCH}-linux' non trovata in index.json"
fi

info "SHA256 atteso : $EXPECTED_SHA256"
ACTUAL_SHA256=$(sha256sum "$TARBALL_CACHE" | awk '{print $1}')
info "SHA256 reale  : $ACTUAL_SHA256"

if [[ "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]]; then
    rm -f "$TARBALL_CACHE"
    error "Checksum SHA256 non corrispondente — tarball rimosso."
fi
info "Checksum verificato."

##############################################################################
# Step 5 — Prepara la struttura per debuild
##############################################################################
info "Preparo la struttura di build in $BUILD_DIR ..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Estrai il tarball upstream
info "Estraggo $TARBALL_CACHE ..."
tar -xf "$TARBALL_CACHE" --strip-components=1 -C "$BUILD_DIR"

# Orig tarball (richiesto da dpkg-buildpackage in formato 3.0 quilt)
if [[ ! -f "$ORIG_TARBALL" ]]; then
    info "Creo orig tarball: $ORIG_TARBALL ..."
    cp "$TARBALL_CACHE" "$ORIG_TARBALL"
fi

# Data di build (usata nei template)
BUILD_DATE=$(date -R)

info "Applico template debian/ per versione ${ZIG_VERSION} ..."

# File statici — copiati così come sono
install_static "control"
install_static "rules"
install_static "compat"
install_static "copyright"
install_static "watch"
install_static "README.Debian"
install_static "zig.doc-base"
install_static "source/format"
install_static "source/local-options"
install_static "source/lintian-overrides"

# File template — @ZIG_VERSION@, @MAINTAINER@, @DATE@, @TARBALL_URL@ sostituiti
install_template "changelog"
install_template "zig.install"
install_template "zig.links"
install_template "zig.dirs"
install_template "zig.lintian-overrides"

# doc/langref.html: aggiunge la riga in zig.install solo se presente nel tarball
if [[ -f "${BUILD_DIR}/doc/langref.html" ]]; then
    echo "doc/langref.html usr/share/doc/zig" >> "${BUILD_DIR}/debian/zig.install"
fi

chmod +x "${BUILD_DIR}/debian/rules"

info "File debian pronti."

##############################################################################
# Step 6 — Esegui debuild
##############################################################################
info "Avvio dpkg-buildpackage in $BUILD_DIR ..."
cd "$BUILD_DIR"
dpkg-buildpackage -b -uc -us

##############################################################################
# Step 7 — Salva il .deb nel pool
##############################################################################
mkdir -p "$OUTPUT_DIR"

DEB_FILE=$(find "${REPO_ROOT}/build" -maxdepth 1 -name "zig_${PKG_VERSION}_*.deb" | head -1)

if [[ -z "$DEB_FILE" ]]; then
    error "File .deb non trovato in ${REPO_ROOT}/build/ dopo dpkg-buildpackage."
fi

cp "$DEB_FILE" "$OUTPUT_DIR/"
DEB_ARTIFACT="${OUTPUT_DIR}/$(basename "$DEB_FILE")"

##############################################################################
# Riepilogo
##############################################################################
echo ""
info "============================================================"
info "Build completato."
info ""
info "  Versione Zig : ${ZIG_VERSION}"
info "  Pacchetto    : $DEB_ARTIFACT"
info "  SHA256 .deb  : $(sha256sum "$DEB_ARTIFACT" | awk '{print $1}')"
info ""
info "Aggiorna l'indice APT con:"
info "  ./scripts/ubuntu-packages.sh"
info "============================================================"
