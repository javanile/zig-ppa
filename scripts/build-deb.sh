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
#   ubuntu/zig_VERSION-1_amd64.deb

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
BUILD_DIR="${REPO_ROOT}/build/zig-${ZIG_VERSION}"
ORIG_TARBALL="${REPO_ROOT}/build/${PKG_NAME}_${ZIG_VERSION}.orig.tar.xz"
OUTPUT_DIR="${REPO_ROOT}/ubuntu"

##############################################################################
# Funzioni
##############################################################################
info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() {
    command -v "$1" &>/dev/null || error "Comando non trovato: $1 — installa con: sudo apt install ${2:-$1}"
}

##############################################################################
# Prerequisiti
##############################################################################
require_cmd curl curl
require_cmd jq jq
require_cmd sha256sum coreutils
require_cmd dpkg-buildpackage dpkg-dev
require_cmd dh debhelper

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

# Estrai il tarball upstream nella directory di build
info "Estraggo $TARBALL_CACHE ..."
tar -xf "$TARBALL_CACHE" --strip-components=1 -C "$BUILD_DIR"

# Crea l'orig tarball (richiesto da dpkg-buildpackage formato 3.0 quilt)
if [[ ! -f "$ORIG_TARBALL" ]]; then
    info "Creo orig tarball: $ORIG_TARBALL ..."
    cp "$TARBALL_CACHE" "$ORIG_TARBALL"
fi

# Copia i file debian nella directory di build
DEBIAN_DIR="${BUILD_DIR}/debian"
mkdir -p "$DEBIAN_DIR/source"

# control
cat > "$DEBIAN_DIR/control" <<EOF
Source: zig
Priority: optional
Section: devel
Maintainer: $MAINTAINER
Build-Depends:
 debhelper (>= 10),
 dpkg-dev (>= 1.19)
Standards-Version: 4.6.2
Homepage: https://ziglang.org

Package: zig
Architecture: amd64
Section: devel
Depends: \${misc:Depends}
Description: General-purpose programming language and toolchain
 Zig is a general-purpose programming language and toolchain for maintaining
 robust, optimal, and reusable software.
 .
 This package contains the Zig executable (zig) as well as the standard
 library.
EOF

# changelog
DATE=$(date -R)
cat > "$DEBIAN_DIR/changelog" <<EOF
zig (${PKG_VERSION}) unstable; urgency=low

  * Package Zig ${ZIG_VERSION} for Ubuntu/Debian.
  * Upstream tarball: ${TARBALL_URL}

 -- ${MAINTAINER}  ${DATE}
EOF

# compat
echo "10" > "$DEBIAN_DIR/compat"

# rules
cat > "$DEBIAN_DIR/rules" <<'EOF'
#!/usr/bin/make -f
export LC_ALL=C.UTF-8
export DH_VERBOSE=1

%:
	dh $@
EOF
chmod +x "$DEBIAN_DIR/rules"

# source/format
echo "3.0 (quilt)" > "$DEBIAN_DIR/source/format"

# zig.dirs
cat > "$DEBIAN_DIR/zig.dirs" <<EOF
usr/lib/zig
usr/lib/zig/${ZIG_VERSION}
EOF

# zig.install — include doc solo se presente nel tarball
INSTALL_CONTENT="zig usr/lib/zig/${ZIG_VERSION}
lib usr/lib/zig/${ZIG_VERSION}"

if [[ -f "${BUILD_DIR}/doc/langref.html" ]]; then
    INSTALL_CONTENT+="
doc/langref.html usr/share/doc/zig"
fi

echo "$INSTALL_CONTENT" > "$DEBIAN_DIR/zig.install"

# zig.links
cat > "$DEBIAN_DIR/zig.links" <<EOF
usr/lib/zig/${ZIG_VERSION}/zig usr/bin/zig
EOF

info "File debian generati per versione ${ZIG_VERSION}."

##############################################################################
# Step 6 — Esegui debuild
##############################################################################
info "Avvio debuild in $BUILD_DIR ..."
cd "$BUILD_DIR"
dpkg-buildpackage -b -uc -us

##############################################################################
# Step 7 — Salva il .deb come artifact
##############################################################################
mkdir -p "$OUTPUT_DIR"

DEB_FILE=$(find "${REPO_ROOT}/build" -maxdepth 1 -name "zig_${PKG_VERSION}_*.deb" | head -1)

if [[ -z "$DEB_FILE" ]]; then
    error "File .deb non trovato in ${REPO_ROOT}/build/ dopo debuild."
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