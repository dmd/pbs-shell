# syntax=docker/dockerfile:1.7

ARG PBS_CLIENT_TAG=v4.0.21-1
ARG PBS_CLIENT_TAG_SHA256=a6c741a347a7dff64dd4d903091ca707891d504e23ed95f374cafbf71c4ff230
ARG PBS_CLIENT_OFFICIAL_DIST=bookworm
ARG PBS_CLIENT_OFFICIAL_KEY_FINGERPRINT=F4E136C67CDCE41AE6DE6FC81140AF8F639E0C39

FROM ubuntu:24.04 AS client
ARG PBS_CLIENT_TAG
ARG PBS_CLIENT_TAG_SHA256
ARG PBS_CLIENT_OFFICIAL_DIST
ARG PBS_CLIENT_OFFICIAL_KEY_FINGERPRINT
ARG TARGETARCH

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl gnupg tar gzip \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    ARCH="${TARGETARCH:-}"; \
    if [ -z "$ARCH" ]; then ARCH="$(dpkg --print-architecture)"; fi; \
    case "$ARCH" in \
      amd64|arm64) ;; \
      *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; \
    esac; \
    mkdir -p /opt/pbs-client; \
    if [ "$ARCH" = "amd64" ]; then \
      REPO_BASE_URL="http://download.proxmox.com/debian/pbs-client"; \
      KEY_URL="https://enterprise.proxmox.com/debian/proxmox-release-${PBS_CLIENT_OFFICIAL_DIST}.gpg"; \
      curl -fsSL "$KEY_URL" -o /tmp/proxmox-release.gpg; \
      key_fpr="$(gpg --show-keys --with-colons /tmp/proxmox-release.gpg | awk -F: '$1=="fpr"{print toupper($10); exit}')"; \
      test "$key_fpr" = "$PBS_CLIENT_OFFICIAL_KEY_FINGERPRINT"; \
      curl -fsSL "${REPO_BASE_URL}/dists/${PBS_CLIENT_OFFICIAL_DIST}/InRelease" -o /tmp/InRelease; \
      gpgv --keyring /tmp/proxmox-release.gpg /tmp/InRelease >/dev/null; \
      PKG_INDEX_PATH="main/binary-amd64/Packages.gz"; \
      PKG_INDEX_SHA256="$(awk -v p="$PKG_INDEX_PATH" '$1 ~ /^[0-9a-fA-F]{64}$/ && $3==p {print $1; exit}' /tmp/InRelease)"; \
      test -n "$PKG_INDEX_SHA256"; \
      curl -fsSL "${REPO_BASE_URL}/dists/${PBS_CLIENT_OFFICIAL_DIST}/${PKG_INDEX_PATH}" -o /tmp/Packages.gz; \
      printf '%s  %s\n' "$PKG_INDEX_SHA256" /tmp/Packages.gz | sha256sum -c -; \
      pkg_meta="$(gzip -dc /tmp/Packages.gz | awk 'BEGIN{RS="";FS="\n"} $1 ~ /^Package: proxmox-backup-client-static$/ {ver="";file="";sha=""; for(i=1;i<=NF;i++){ if($i ~ /^Version: /) ver=substr($i,10); else if($i ~ /^Filename: /) file=substr($i,11); else if($i ~ /^SHA256: /) sha=substr($i,9) } if(ver != "" && file != "" && sha != "") print ver "|" file "|" sha }' | sort -V | tail -n1)"; \
      test -n "$pkg_meta"; \
      pkg_ver="${pkg_meta%%|*}"; \
      pkg_file_and_sha="${pkg_meta#*|}"; \
      pkg_file="${pkg_file_and_sha%%|*}"; \
      pkg_sha256="${pkg_file_and_sha##*|}"; \
      test -n "$pkg_sha256"; \
      PKG_URL="${REPO_BASE_URL}/${pkg_file}"; \
      echo "Using official Proxmox client package: ${pkg_ver}"; \
      curl -fsSL "$PKG_URL" -o /tmp/proxmox-backup-client-static.deb; \
      printf '%s  %s\n' "$pkg_sha256" /tmp/proxmox-backup-client-static.deb | sha256sum -c -; \
      dpkg-deb -x /tmp/proxmox-backup-client-static.deb /tmp/pbs-client; \
      cp /tmp/pbs-client/usr/bin/proxmox-backup-client /opt/pbs-client/proxmox-backup-client; \
      cp /tmp/pbs-client/usr/bin/pxar /opt/pbs-client/pxar; \
    else \
      echo "WARNING: official Proxmox static client source is amd64-only; falling back to ayufan release artifact for ${ARCH}" >&2; \
      URL="https://github.com/ayufan/pve-backup-server-dockerfiles/releases/download/${PBS_CLIENT_TAG}/proxmox-backup-client-${PBS_CLIENT_TAG}-${ARCH}.tgz"; \
      curl -fsSL "$URL" -o /tmp/proxmox-backup-client.tgz; \
      printf '%s  %s\n' "$PBS_CLIENT_TAG_SHA256" /tmp/proxmox-backup-client.tgz | sha256sum -c -; \
      tar -xzf /tmp/proxmox-backup-client.tgz -C /opt/pbs-client --strip-components=1; \
    fi; \
    test -x /opt/pbs-client/proxmox-backup-client; \
    if [ "$ARCH" = "$(dpkg --print-architecture)" ]; then \
      /opt/pbs-client/proxmox-backup-client version; \
    else \
      echo "Skipping client version execution during cross-arch build (${ARCH} on $(dpkg --print-architecture))"; \
    fi

FROM ubuntu:24.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      emacs-nox \
      fuse3 \
      jq \
      less \
      lvm2 \
      mount \
      openssh-client \
      tar \
      util-linux \
      vim \
      whiptail \
    && rm -rf /var/lib/apt/lists/*

COPY --from=client /opt/pbs-client/proxmox-backup-client /usr/local/bin/proxmox-backup-client
COPY --from=client /opt/pbs-client/pxar /usr/local/bin/pxar
COPY pbs-snapshot-browser /usr/local/bin/pbs-snapshot-browser

RUN chmod +x /usr/local/bin/pbs-snapshot-browser /usr/local/bin/proxmox-backup-client /usr/local/bin/pxar

WORKDIR /work
ENV AUTH_FILE=/app/auth.env
ENTRYPOINT ["/usr/local/bin/pbs-snapshot-browser"]
