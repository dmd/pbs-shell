# syntax=docker/dockerfile:1.7

ARG PBS_CLIENT_TAG=v4.0.21-1
ARG PBS_CLIENT_OFFICIAL_DIST=bookworm

FROM ubuntu:24.04 AS client
ARG PBS_CLIENT_TAG
ARG PBS_CLIENT_OFFICIAL_DIST
ARG TARGETARCH

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl tar gzip \
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
      PKG_INDEX_URL="http://download.proxmox.com/debian/pbs-client/dists/${PBS_CLIENT_OFFICIAL_DIST}/main/binary-amd64/Packages.gz"; \
      pkg_meta="$(curl -fsSL "$PKG_INDEX_URL" | gzip -dc | awk 'BEGIN{RS="";FS="\n"} $1 ~ /^Package: proxmox-backup-client-static$/ {ver="";file=""; for(i=1;i<=NF;i++){ if($i ~ /^Version: /) ver=substr($i,10); else if($i ~ /^Filename: /) file=substr($i,11) } if(ver != "" && file != "") print ver "|" file }' | sort -V | tail -n1)"; \
      test -n "$pkg_meta"; \
      pkg_ver="${pkg_meta%%|*}"; \
      pkg_file="${pkg_meta#*|}"; \
      PKG_URL="http://download.proxmox.com/debian/pbs-client/${pkg_file}"; \
      echo "Using official Proxmox client package: ${pkg_ver}"; \
      curl -fsSL "$PKG_URL" -o /tmp/proxmox-backup-client-static.deb; \
      dpkg-deb -x /tmp/proxmox-backup-client-static.deb /tmp/pbs-client; \
      cp /tmp/pbs-client/usr/bin/proxmox-backup-client /opt/pbs-client/proxmox-backup-client; \
      cp /tmp/pbs-client/usr/bin/pxar /opt/pbs-client/pxar; \
    else \
      echo "WARNING: official Proxmox static client source is amd64-only; falling back to ayufan release artifact for ${ARCH}" >&2; \
      URL="https://github.com/ayufan/pve-backup-server-dockerfiles/releases/download/${PBS_CLIENT_TAG}/proxmox-backup-client-${PBS_CLIENT_TAG}-${ARCH}.tgz"; \
      curl -fsSL "$URL" -o /tmp/proxmox-backup-client.tgz; \
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
