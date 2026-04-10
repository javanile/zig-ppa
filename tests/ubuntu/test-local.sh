#!/usr/bin/env bash
# test-local.sh — Testa l'installazione di Zig dal PPA su questa macchina Ubuntu
#
# Uso:
#   sudo bash tests/ubuntu/test-local.sh
#   sudo bash tests/ubuntu/test-local.sh 0.13.0
#   sudo bash tests/ubuntu/test-local.sh 0.13.0 https://javanile.org/zig-ppa/ubuntu
#
# Il test è non distruttivo: al termine chiede se rimuovere tutto ciò che ha aggiunto.

set -euo pipefail

##############################################################################
# Argomenti
##############################################################################
ZIG_VERSION="${1:-0.13.0}"
PPA_URL="${2:-https://javanile.org/zig-ppa/ubuntu}"

##############################################################################
# Configurazione
##############################################################################
KEYRING_FILE="/usr/share/keyrings/zig-ppa.gpg"
SOURCES_FILE="/etc/apt/sources.list.d/zig-ppa.list"

##############################################################################
# Controllo privilegi
##############################################################################
if [[ "$EUID" -ne 0 ]]; then
    echo "[ERRORE] Esegui con sudo: sudo bash $0" >&2
    exit 1
fi

##############################################################################
# Rilevamento distro
##############################################################################
if [[ ! -f /etc/os-release ]]; then
    echo "[ERRORE] Impossibile rilevare la distribuzione (/etc/os-release non trovato)." >&2
    exit 1
fi

source /etc/os-release
UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"

if [[ -z "$UBUNTU_CODENAME" ]]; then
    echo "[ERRORE] Codename Ubuntu non rilevato — imposta manualmente UBUNTU_CODENAME." >&2
    exit 1
fi

##############################################################################
# Intestazione
##############################################################################
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Zig PPA — Test installazione locale                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Distro      : ${PRETTY_NAME}"
echo "  Codename    : ${UBUNTU_CODENAME}"
echo "  Zig version : ${ZIG_VERSION}"
echo "  PPA URL     : ${PPA_URL}"
echo ""

##############################################################################
# Funzioni
##############################################################################
step() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  STEP $1 — $2"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

ok()    { echo "  [OK]    $*"; }
info()  { echo "  [INFO]  $*"; }
warn()  { echo "  [WARN]  $*"; }
fail()  { echo "  [FAIL]  $*" >&2; }

cleanup() {
    echo ""
    read -rp "Rimuovere chiave, sources.list e pacchetto zig installato? [s/N] " ans
    if [[ "${ans,,}" == "s" ]]; then
        apt-get remove -y zig 2>/dev/null && ok "zig rimosso." || warn "zig non era installato."
        rm -f "$KEYRING_FILE" && ok "Keyring rimosso: $KEYRING_FILE"
        rm -f "$SOURCES_FILE" && ok "Sources rimosso: $SOURCES_FILE"
        apt-get update -qq
        ok "Pulizia completata."
    else
        info "Lasciato tutto installato."
    fi
}
trap cleanup EXIT

##############################################################################
# STEP 1 — Prerequisiti
##############################################################################
step 1 "Installa prerequisiti (ca-certificates, curl, gnupg)"

apt-get update -y
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg
ok "Prerequisiti installati."

##############################################################################
# STEP 2 — Aggiunge la chiave GPG
##############################################################################
step 2 "Aggiunge la chiave GPG del PPA"

KEY_URL="${PPA_URL}/key.gpg"
info "Scarico chiave da: $KEY_URL"

curl --fail --silent --show-error --location "$KEY_URL" \
    | gpg --dearmor \
    | tee "$KEYRING_FILE" > /dev/null

info "Chiave salvata in: $KEYRING_FILE"
info "Fingerprint:"
gpg --no-default-keyring \
    --keyring "$KEYRING_FILE" \
    --fingerprint 2>/dev/null | sed 's/^/    /'
ok "Chiave GPG aggiunta."

##############################################################################
# STEP 3 — Aggiunge il sources.list
##############################################################################
step 3 "Aggiunge il repository APT"

SOURCE_LINE="deb [signed-by=${KEYRING_FILE}] ${PPA_URL} ${UBUNTU_CODENAME} main"
info "Riga sorgente: $SOURCE_LINE"
echo "$SOURCE_LINE" > "$SOURCES_FILE"

ok "Sorgente salvata in: $SOURCES_FILE"

##############################################################################
# STEP 4 — apt-get update
##############################################################################
step 4 "Aggiorna l'indice APT"

apt-get update -y

info "Versioni zig disponibili nel PPA:"
apt-cache policy zig 2>/dev/null | sed 's/^/    /' || warn "Pacchetto zig non ancora visibile."

ok "Indice aggiornato."

##############################################################################
# STEP 5 — Installa Zig (versione specifica)
##############################################################################
step 5 "Installa zig=${ZIG_VERSION}-1"

apt-get install -y \
    --no-install-recommends \
    --verbose-versions \
    "zig=${ZIG_VERSION}-1"

ok "Pacchetto installato."

##############################################################################
# STEP 6 — Verifica
##############################################################################
step 6 "Verifica installazione"

info "Percorso binario:"
which zig | sed 's/^/    /'

info "Versione riportata:"
zig version | sed 's/^/    /'

INSTALLED_VERSION="$(zig version)"
if [[ "$INSTALLED_VERSION" == "$ZIG_VERSION" ]]; then
    ok "Versione corretta: $INSTALLED_VERSION"
else
    fail "Versione attesa: $ZIG_VERSION — trovata: $INSTALLED_VERSION"
    exit 1
fi

info "Dettagli pacchetto dpkg:"
dpkg -s zig | sed 's/^/    /'

##############################################################################
# STEP 7 — Smoke test
##############################################################################
step 7 "Smoke test — zig init + zig build run"

TMPDIR="$(mktemp -d)"
info "Directory temporanea: $TMPDIR"

RUNNER="${SUDO_USER:-root}"
info "Eseguo come utente: $RUNNER"

su -s /bin/bash "$RUNNER" -c "
    cd '$TMPDIR'
    zig init
    echo ''
    echo '--- zig build run output ---'
    zig build run
    echo '----------------------------'
" && ok "Smoke test superato." || { fail "Smoke test fallito."; exit 1; }

rm -rf "$TMPDIR"

##############################################################################
# Riepilogo
##############################################################################
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    TEST COMPLETATO OK                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  zig $(zig version) installato correttamente su ${PRETTY_NAME}"
echo ""
