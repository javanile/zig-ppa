# TODO — zig-ppa

Traccia delle attività necessarie per rendere funzionante il PPA Zig su Ubuntu/Debian
servito da `https://javanile.org/zig-ppa/ubuntu/`.

---

## 1. File del repository APT

### 1.1 Creare `ubuntu/sources.list`
- Creare la directory `ubuntu/`
- Scrivere il file `ubuntu/sources.list` con il contenuto:
  ```
  deb https://javanile.org/zig-ppa/ubuntu focal main
  ```
- Verificare che il file sia scaricabile via curl senza redirect problematici
- Valutare se servire varianti per distro diverse (focal, jammy, noble) o un unico file universale

### 1.2 Generare la chiave GPG e aggiungere `ubuntu/key.gpg`
- Generare una chiave GPG dedicata al progetto (es. `zig-ppa@javanile.org`)
- Esportare la chiave pubblica in formato ASCII armored: `gpg --export --armor`
- Salvare il file come `ubuntu/key.gpg`
- Salvare la chiave privata in modo sicuro come GitHub Secret (`GPG_PRIVATE_KEY` + `GPG_PASSPHRASE`)
- Documentare la procedura di rinnovo della chiave

### 1.3 Creare i file indice APT
- Generare `ubuntu/Packages` (lista dei pacchetti disponibili con checksum)
- Generare `ubuntu/Packages.gz` (versione compressa)
- Generare `ubuntu/Release` (metadati del repository: origin, label, codename, date, checksum)
- Firmare e generare `ubuntu/InRelease` (Release firmato inline con GPG)
- Generare `ubuntu/Release.gpg` (firma detached)
- Automatizzare la rigenerazione di questi file ad ogni nuova versione

---

## 2. Aggiornamento pacchetto Zig

### 2.1 Aggiornare `control`
- Cambiare `Maintainer` da `Arto Bendiken` a `Francesco Bianco <francescobianco@javanile.org>` (o simile)
- Aggiornare `Standards-Version` all'ultima disponibile (es. 4.6.2)
- Rimuovere `Vcs-Git` e `Vcs-Browser` se non pertinenti al fork
- Aggiungere `Architecture: amd64 arm64` se si vuole supporto multi-arch

### 2.2 Aggiornare `changelog`
- Aggiungere entry per ogni versione Zig da distribuire (es. 0.11.0, 0.12.0, 0.13.0)
- Seguire il formato Debian standard: `zig (VERSION-1) unstable; urgency=low`
- Specificare URL del tarball upstream in ogni entry

### 2.3 Aggiornare `zig.install`
- Aggiornare i path dalla versione 0.6.0 alla versione corrente
- Verificare che la struttura delle directory nel tarball upstream non sia cambiata
- Esempio attuale da aggiornare:
  ```
  zig /usr/lib/zig/0.6.0   →   zig /usr/lib/zig/VERSION
  lib /usr/lib/zig/0.6.0   →   lib /usr/lib/zig/VERSION
  ```

### 2.4 Aggiornare `zig.links`
- Aggiornare il symlink `/usr/lib/zig/VERSION/zig → /usr/bin/zig` con la versione corrente
- Verificare compatibilità con aggiornamenti futuri (symlink versioned vs. unversioned)

### 2.5 Valutare supporto multi-versione
- Decidere se distribuire solo l'ultima stable o anche versioni precedenti
- Valutare se includere nightly/dev builds con nome pacchetto separato (es. `zig-nightly`)

---

## 3. GitHub Actions — CI/CD

### 3.1 Workflow `build.yml` — Build del pacchetto .deb
- Trigger: push su `main`, manualmente (`workflow_dispatch`), e su nuovi tag `vX.Y.Z`
- Steps:
  1. Checkout del repo
  2. Installare dipendenze: `debhelper`, `dpkg-dev`, `devscripts`
  3. Scaricare il tarball ufficiale da `https://ziglang.org/download/VERSION/zig-linux-x86_64-VERSION.tar.xz`
  4. Verificare il checksum SHA256 del tarball
  5. Preparare la struttura per `debuild` (symlink + orig tarball)
  6. Eseguire `debuild -b -uc -us` per buildare il `.deb`
  7. Salvare il `.deb` come artifact del workflow

### 3.2 Workflow `publish.yml` — Pubblicazione del repository APT
- Trigger: al completamento di `build.yml` o manualmente
- Steps:
  1. Scaricare i `.deb` dagli artifact
  2. Importare la chiave GPG privata da GitHub Secrets
  3. Rigenerare `Packages`, `Packages.gz`
  4. Rigenerare e firmare `Release`, `InRelease`, `Release.gpg`
  5. Pubblicare su GitHub Pages (branch `gh-pages`) oppure su hosting esterno via rsync/sftp
  6. Aggiornare `ubuntu/sources.list` e `ubuntu/key.gpg` se necessario

### 3.3 Workflow `update-check.yml` — Controllo nuove versioni Zig
- Trigger: schedulato settimanalmente (cron)
- Steps:
  1. Fetch della pagina `https://ziglang.org/download/index.json`
  2. Confrontare la versione upstream con quella nel `changelog`
  3. Se disponibile nuova versione: aprire automaticamente una PR o creare un issue

---

## 4. Makefile — Target utili

### 4.1 Aggiungere target `build`
- Scaricare il tarball Zig della versione specificata
- Preparare la struttura e lanciare `debuild`
- Output: file `.deb` nella directory corrente

### 4.2 Aggiungere target `sign`
- Firmare il `.deb` con la chiave GPG locale
- Rigenerare i file `Packages`, `Release`, `InRelease`

### 4.3 Aggiungere target `publish`
- Copiare i file del repository nella directory `ubuntu/`
- Pushare su GitHub Pages o sul server di hosting

### 4.4 Aggiungere target `verify`
- Testare l'installazione in un container Docker Ubuntu pulito
- Simulare i comandi del README e verificare che `zig --version` funzioni

### 4.5 Esempio struttura Makefile target:
```makefile
ZIG_VERSION ?= 0.13.0

build:
sign:
publish:
verify:
clean:
```

---

## 5. README.md

### 5.1 Aggiornare con contenuto completo
- Aggiungere descrizione del progetto (cos'è, a chi serve)
- Mantenere le istruzioni di installazione rapida (già presenti)
- Aggiungere sezione **Versioni supportate** con tabella distro/arch
- Aggiungere sezione **Come funziona** (flusso build → sign → publish)
- Aggiungere sezione **Contributing** per chi vuole contribuire
- Aggiungere badge: CI status, versione Zig disponibile, licenza

---

## 6. Infrastruttura di hosting

### 6.1 Decidere dove servire i file
- **Opzione A**: GitHub Pages sul branch `gh-pages` (gratuito, ma dominio `github.io` a meno di CNAME)
- **Opzione B**: Hosting esterno `javanile.org` con deploy via rsync/sftp/scp
- **Opzione C**: Cloudflare Pages o Netlify (gratuiti, con dominio custom)

### 6.2 Configurare il dominio
- Verificare che `https://javanile.org/zig-ppa/ubuntu/` risponda correttamente
- Assicurarsi che i file siano serviti con Content-Type corretto (no redirect che rompono `apt`)
- Testare con `curl -v` che `key.gpg` e `sources.list` siano accessibili

### 6.3 Testare end-to-end
- Usare un container Docker `ubuntu:focal` / `ubuntu:jammy` / `ubuntu:noble`
- Eseguire i comandi del README dall'inizio alla fine
- Verificare che `sudo apt install zig` installi correttamente e `zig version` funzioni