# zig-ppa

[![Ubuntu PPA Install Test](https://github.com/javanile/zig-ppa/actions/workflows/ubuntu.yml/badge.svg)](https://github.com/javanile/zig-ppa/actions/workflows/ubuntu.yml)
[![Zig Version](https://img.shields.io/badge/zig-0.13.0-f7a41d?logo=zig&logoColor=white)](https://ziglang.org/download/)
[![Ubuntu](https://img.shields.io/badge/ubuntu-focal%20%7C%20jammy%20%7C%20noble-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com)
[![License](https://img.shields.io/badge/license-Unlicense-blue.svg)](UNLICENSE)

Unofficial APT repository for the [Zig](https://ziglang.org) programming language on Ubuntu.  
Install and update Zig like any other system package — no manual downloads, no PATH hacks.

---

## Quick install

```bash
# 1. Add the GPG key
curl -fsSL https://javanile.org/zig-ppa/ubuntu/key.gpg \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/zig-ppa.gpg > /dev/null

# 2. Add the repository (replace "focal" with your Ubuntu codename)
echo "deb [signed-by=/usr/share/keyrings/zig-ppa.gpg] https://javanile.org/zig-ppa/ubuntu focal main" \
  | sudo tee /etc/apt/sources.list.d/zig-ppa.list

# 3. Install Zig
sudo apt update
sudo apt install zig
```

> **Your Ubuntu codename?** Run `lsb_release -cs` to find out.

### Install a specific version

```bash
sudo apt install zig=0.13.0-1
```

### Verify the installation

```bash
zig version
```

---

## Supported platforms

| Ubuntu release   | Codename | amd64 | arm64 |
|:-----------------|:---------|:------|:------|
| Ubuntu 24.04 LTS | noble    | yes   | yes   |
| Ubuntu 22.04 LTS | jammy    | yes   | yes   |
| Ubuntu 20.04 LTS | focal    | yes   | yes   |

---

## How it works

```
ziglang.org/download/          GitHub Actions (build.yml)
       │                               │
       │  official tarball             │  build-deb.sh
       └──────────────────────────────►│
                                       │  dpkg-buildpackage
                                       │
                                       ▼
                              ubuntu/pool/main/z/zig/
                              ubuntu/dists/<codename>/
                                       │
                                       │  ubuntu-packages.sh
                                       │  (Packages + Release + GPG sign)
                                       │
                                       ▼
                         https://javanile.org/zig-ppa/ubuntu/
```

1. **Build** — `scripts/build-deb.sh <version>` downloads the official upstream tarball, verifies its SHA256 against [ziglang.org/download/index.json](https://ziglang.org/download/index.json), and builds a `.deb` with `dpkg-buildpackage`.
2. **Publish** — `scripts/ubuntu-packages.sh` regenerates `Packages`, `Release`, `InRelease`, and `Release.gpg` for each supported Ubuntu release and places them under `ubuntu/dists/`.
3. **Serve** — the `ubuntu/` directory is served as a static site via GitHub Pages at `https://javanile.org/zig-ppa/ubuntu/`.

---

## Repository layout

```
debian/          Debian packaging templates (control, rules, zig.install …)
scripts/
  build-deb.sh       Build a .deb for a given Zig version
  ubuntu-packages.sh Regenerate APT index files and GPG signatures
  ubuntu-gpg-key.sh  Generate / renew the repository signing key
tests/ubuntu/
  Dockerfile         Docker-based end-to-end install test
  test-local.sh      Run the full install test on this machine
ubuntu/
  key.gpg            Repository public key (add this to your keyring)
  sources.list       Example sources.list for users
  pool/main/z/zig/   .deb packages
  dists/<codename>/  APT index files (generated)
.github/workflows/
  ubuntu.yml         Matrix CI: Zig version × Ubuntu codename
```

---

## Contributing

Pull requests are welcome. To add a new Zig version:

1. Run `./scripts/build-deb.sh <new-version>` locally.
2. Run `./scripts/ubuntu-packages.sh` to regenerate the index.
3. Add the new version pairs to the matrix in `.github/workflows/ubuntu.yml`.
4. Open a PR — CI will validate the install on all supported distros.

To test locally before opening a PR:

```bash
sudo bash tests/ubuntu/test-local.sh <version>
```

---

## Maintainer

**Francesco Bianco** — [bianco@javanile.org](mailto:bianco@javanile.org)  
Original packaging by [Arto Bendiken](https://github.com/artob).

Zig is developed by the [Zig Software Foundation](https://ziglang.org/zsf/).  
This repository is not affiliated with or endorsed by the Zig project.
