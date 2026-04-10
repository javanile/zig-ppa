#!/usr/bin/env bash
# ubuntu-gpg-key.sh — Genera la coppia di chiavi GPG per il PPA zig-ppa@javanile.org
#
# Uso:
#   ./ubuntu-gpg-key.sh           # genera nuova chiave
#   ./ubuntu-gpg-key.sh --renew   # rinnova la chiave esistente (stessa identità)
#
# Output:
#   ubuntu/key.gpg          — chiave pubblica (ASCII armored) → committata nel repo
#   ubuntu/private.gpg  — chiave privata (ASCII armored) → in .gitignore, custodia manuale
#
# Per il rinnovo manuale riponi ubuntu/private.gpg nella directory ubuntu/
# prima di eseguire ./scripts/ubuntu-gpg-key.sh --renew

set -euo pipefail

##############################################################################
# Configurazione
##############################################################################
GPG_NAME="Zig PPA"
GPG_EMAIL="zig-ppa@javanile.org"
GPG_COMMENT="Javanile Zig PPA signing key"
GPG_KEY_TYPE="eddsa"
GPG_KEY_CURVE="Ed25519"
GPG_EXPIRE="2y"

PUBLIC_KEY_FILE="ubuntu/key.gpg"
PRIVATE_KEY_FILE="ubuntu/private.gpg"
BATCH_FILE="$(mktemp /tmp/gpg-batch.XXXXXX)"

##############################################################################
# Funzioni di supporto
##############################################################################
info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() { command -v "$1" &>/dev/null || error "Comando non trovato: $1"; }

cleanup() { rm -f "$BATCH_FILE"; }
trap cleanup EXIT

##############################################################################
# Controlli prerequisiti
##############################################################################
require_cmd gpg

RENEW=false
[[ "${1:-}" == "--renew" ]] && RENEW=true

##############################################################################
# Verifica se la chiave esiste già nel keyring
##############################################################################
KEY_FP=""
KEY_FP=$(gpg --list-secret-keys --with-colons 2>/dev/null \
    | awk -F: '/^fpr:/ { print $10 }' \
    | while read -r fp; do
        uid=$(gpg --list-secret-keys --with-colons "$fp" 2>/dev/null \
              | awk -F: '/^uid:/ { print $10 }' | head -1)
        if echo "$uid" | grep -q "$GPG_EMAIL"; then echo "$fp"; fi
      done | head -1)

if [[ -n "$KEY_FP" && "$RENEW" == "false" ]]; then
    warn "Chiave per $GPG_EMAIL già presente nel keyring (fingerprint: $KEY_FP)."
    warn "Usa --renew per rigenerare, oppure esporta direttamente."
    read -rp "Esportare la chiave esistente? [s/N] " ans
    [[ "${ans,,}" == "s" ]] || exit 0
fi

##############################################################################
# Import chiave privata (per --renew)
##############################################################################
if [[ "$RENEW" == "true" ]]; then
    if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
        error "File chiave privata non trovato: $PRIVATE_KEY_FILE"$'\n'"Riponi il file prima di eseguire --renew."
    fi
    info "Importo la chiave privata da $PRIVATE_KEY_FILE ..."
    gpg --import "$PRIVATE_KEY_FILE"
    KEY_FP=$(gpg --list-secret-keys --with-colons "$GPG_EMAIL" 2>/dev/null \
        | awk -F: '/^fpr:/ { print $10 }' | head -1)
    [[ -n "$KEY_FP" ]] || error "Import fallito: fingerprint non trovato."
    info "Chiave importata: $KEY_FP"

    # Estende la scadenza della chiave esistente
    info "Estendo la scadenza a $GPG_EXPIRE ..."
    gpg --quick-set-expire "$KEY_FP" "$GPG_EXPIRE"
fi

##############################################################################
# Generazione nuova chiave (solo se non in --renew o keyring vuoto)
##############################################################################
if [[ -z "$KEY_FP" ]]; then
    info "Genero nuova chiave GPG ($GPG_KEY_CURVE, scadenza $GPG_EXPIRE) ..."

    cat > "$BATCH_FILE" <<EOF
%no-protection
Key-Type: $GPG_KEY_TYPE
Key-Curve: $GPG_KEY_CURVE
Key-Usage: sign
Name-Real: $GPG_NAME
Name-Comment: $GPG_COMMENT
Name-Email: $GPG_EMAIL
Expire-Date: $GPG_EXPIRE
%commit
EOF

    gpg --batch --gen-key "$BATCH_FILE"

    KEY_FP=$(gpg --list-secret-keys --with-colons "$GPG_EMAIL" 2>/dev/null \
        | awk -F: '/^fpr:/ { print $10 }' | head -1)
    [[ -n "$KEY_FP" ]] || error "Generazione chiave fallita."
    info "Chiave generata: $KEY_FP"
fi

##############################################################################
# Esporta chiave pubblica → ubuntu/key.gpg
##############################################################################
info "Esporto chiave pubblica → $PUBLIC_KEY_FILE"
mkdir -p "$(dirname "$PUBLIC_KEY_FILE")"
gpg --export --armor "$KEY_FP" > "$PUBLIC_KEY_FILE"
echo ""
echo "=== $PUBLIC_KEY_FILE ==="
head -3 "$PUBLIC_KEY_FILE"
echo "..."

##############################################################################
# Esporta chiave privata → ubuntu/private.gpg
##############################################################################
info "Esporto chiave privata → $PRIVATE_KEY_FILE"
mkdir -p "$(dirname "$PRIVATE_KEY_FILE")"
gpg --export-secret-keys --armor "$KEY_FP" > "$PRIVATE_KEY_FILE"
chmod 600 "$PRIVATE_KEY_FILE"

##############################################################################
# Riepilogo
##############################################################################
echo ""
info "============================================================"
info "Chiave GPG pronta."
info ""
info "  Fingerprint : $KEY_FP"
info "  Pubblica    : $PUBLIC_KEY_FILE  (da committare)"
info "  Privata     : $PRIVATE_KEY_FILE  (NON committare — in .gitignore)"
info ""
info "Per GitHub Actions, carica questi due secret:"
info "  GPG_PRIVATE_KEY  = contenuto di $PRIVATE_KEY_FILE"
info "  GPG_PASSPHRASE   = (vuota se la chiave non è protetta da passphrase)"
info ""
info "Per caricare GPG_PRIVATE_KEY via gh CLI:"
info "  gh secret set GPG_PRIVATE_KEY < $PRIVATE_KEY_FILE"
info ""
info "Rinnovo manuale (alla scadenza):"
info "  1. Riponi $PRIVATE_KEY_FILE nella directory ubuntu/"
info "  2. Esegui: ./scripts/ubuntu-gpg-key.sh --renew"
info "  3. Committa il nuovo $PUBLIC_KEY_FILE"
info "  4. Aggiorna il secret GPG_PRIVATE_KEY su GitHub"
info "============================================================"