# Dockerfile — Test installazione Zig dal PPA zig-ppa@javanile.org
#
# Build args:
#   UBUNTU_CODENAME   focal | jammy | noble          (default: focal)
#   ZIG_VERSION       0.13.0 | 0.12.0 | ...          (default: 0.13.0)
#   PPA_URL           base URL del repository APT     (default: produzione)
#
# Uso locale:
#   docker build \
#     --build-arg UBUNTU_CODENAME=focal \
#     --build-arg ZIG_VERSION=0.13.0 \
#     -t zig-ppa-test .
#
#   docker run --rm zig-ppa-test

ARG UBUNTU_CODENAME=focal
FROM ubuntu:${UBUNTU_CODENAME}

ARG UBUNTU_CODENAME=focal
ARG ZIG_VERSION=0.13.0
ARG PPA_URL=https://javanile.org/zig-ppa/ubuntu

ENV DEBIAN_FRONTEND=noninteractive
ENV ZIG_VERSION=${ZIG_VERSION}
ENV UBUNTU_CODENAME=${UBUNTU_CODENAME}

# Step 1 — prerequisiti minimi
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
    && rm -rf /var/lib/apt/lists/*

# Step 2 — aggiunge la chiave GPG del PPA
RUN curl -fsSL "${PPA_URL}/key.gpg" \
        | gpg --dearmor \
        | tee /usr/share/keyrings/zig-ppa.gpg > /dev/null

# Step 3 — aggiunge il sources.list
RUN echo "deb [signed-by=/usr/share/keyrings/zig-ppa.gpg] ${PPA_URL} ${UBUNTU_CODENAME} main" \
        > /etc/apt/sources.list.d/zig-ppa.list

# Step 4 — installa Zig (versione specifica)
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        "zig=${ZIG_VERSION}-1" \
    && rm -rf /var/lib/apt/lists/*

# Step 5 — verifica
RUN zig version && \
    test "$(zig version)" = "${ZIG_VERSION}" || \
    { echo "ERRORE: versione attesa ${ZIG_VERSION}, trovata $(zig version)"; exit 1; }

CMD ["zig", "version"]
