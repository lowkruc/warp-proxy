ARG BASE_IMAGE=debian:bookworm-slim

# ---- Stage 1: prepare GOST + cloudflare-warp binaries ----
FROM debian:bookworm-slim AS downloader
ARG GOST_VERSION
ARG TARGETPLATFORM
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates gnupg binutils && \
    # dearmor cloudflare key
    mkdir -p /usr/share/keyrings && \
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
      | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    # add cloudflare repo
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ bookworm main" \
      > /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    # download cloudflare-warp .deb without installing
    cd /tmp && apt-get download cloudflare-warp && \
    mkdir -p /warp-extract && \
    dpkg -x /tmp/cloudflare-warp*.deb /warp-extract && \
    # strip debug symbols from binaries (~15MB saved)
    strip --strip-unneeded /warp-extract/bin/warp-svc 2>/dev/null || true && \
    strip --strip-unneeded /warp-extract/bin/warp-cli 2>/dev/null || true && \
    strip --strip-unneeded /warp-extract/bin/warp-dex 2>/dev/null || true && \
    # download GOST
    case ${TARGETPLATFORM} in \
      "linux/amd64")   ARCH="amd64" ;; \
      "linux/arm64")   ARCH="armv8" ;; \
      *) echo "Unsupported TARGETPLATFORM: ${TARGETPLATFORM}" && exit 1 ;; \
    esac && \
    MAJOR=$(echo ${GOST_VERSION} | cut -d. -f1) && \
    MINOR=$(echo ${GOST_VERSION} | cut -d. -f2) && \
    if [ "${MAJOR}" -ge 3 ] || [ "${MAJOR}" -eq 2 -a "${MINOR}" -ge 12 ]; then \
      [ "${TARGETPLATFORM}" = "linux/arm64" ] && ARCH="arm64"; \
      FILE="gost_${GOST_VERSION}_linux_${ARCH}.tar.gz"; \
      curl -fSL "https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/${FILE}" -o /tmp/gost.tar.gz && \
      tar -xzf /tmp/gost.tar.gz -C /tmp/ gost; \
    else \
      FILE="gost-linux-${ARCH}-${GOST_VERSION}.gz"; \
      curl -fSL "https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/${FILE}" -o /tmp/gost.gz && \
      gunzip /tmp/gost.gz && mv /tmp/${FILE%.gz} /tmp/gost; \
    fi && \
    chmod +x /tmp/gost

# ---- Stage 2: final image ----
FROM ${BASE_IMAGE}

ARG WARP_VERSION
ARG GOST_VERSION
ARG COMMIT_SHA

LABEL org.opencontainers.image.authors="cmj2002"
LABEL org.opencontainers.image.url="https://github.com/cmj2002/warp-docker"
LABEL WARP_VERSION=${WARP_VERSION}
LABEL GOST_VERSION=${GOST_VERSION}
LABEL COMMIT_SHA=${COMMIT_SHA}

# copy GOST
COPY --from=downloader /tmp/gost /usr/bin/gost

# copy only warp-svc, warp-cli, warp-dex (skip GUI: taskbar, flutter libs)
COPY --from=downloader /warp-extract/bin/warp-svc /usr/bin/warp-svc
COPY --from=downloader /warp-extract/bin/warp-cli /usr/bin/warp-cli
COPY --from=downloader /warp-extract/bin/warp-dex /usr/bin/warp-dex

# copy service files
COPY --from=downloader /warp-extract/etc/ /etc/
COPY --from=downloader /warp-extract/lib/ /lib/

# copy cloudflare key
RUN mkdir -p /usr/share/keyrings
COPY --from=downloader /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

COPY entrypoint.sh /entrypoint.sh
COPY ./healthcheck /healthcheck

# install minimal runtime deps + aggressive cleanup
RUN chmod +x /entrypoint.sh /healthcheck/index.sh && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      curl ca-certificates sudo dbus \
      libnftables1 libnftnl11 libmnl0 \
      libpcsclite1 libcap2-bin \
      libglib2.0-0 libdbus-1-3 libsystemd0 \
      libssl3 libnss3 libnspr4 \
      libtss2-esys-3.0.2-0 libtss2-tctildr0 libtss2-mu0 \
      iproute2 && \
    # remove unnecessary packages
    apt-get purge -y --auto-remove \
      e2fsprogs e2fsck-static mke2fs e2scrub 2>/dev/null || true && \
    # aggressive cleanup
    rm -rf /var/lib/apt/lists/* \
           /var/cache/apt/archives/* \
           /var/log/* \
           /usr/share/doc/* \
           /usr/share/man/* \
           /usr/share/info/* \
           /usr/share/locale/* \
           /usr/share/terminfo/* \
           /lib/terminfo/* \
           /lib/udev \
           /usr/lib/udev \
           /usr/sbin/e2fs* \
           /usr/sbin/debugfs \
           /usr/sbin/dumpe2fs \
           /usr/sbin/tune2fs \
           /usr/sbin/e4defrag \
           /usr/sbin/mke2fs \
           /usr/sbin/mkfs* \
           /usr/sbin/fsck* \
           /usr/sbin/findfs \
           /usr/sbin/logsave \
           /usr/sbin/pivot_root \
           /usr/sbin/switch_root \
           /usr/sbin/zramctl \
           /usr/sbin/zic \
           /tmp/* && \
    # create warp user
    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp

USER warp

# Accept Cloudflare WARP TOS
RUN mkdir -p /home/warp/.local/share/warp && \
    echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt

ENV GOST_ARGS="-L :1080"
ENV WARP_SLEEP=2
ENV REGISTER_WHEN_MDM_EXISTS=
ENV WARP_LICENSE_KEY=
ENV BETA_FIX_HOST_CONNECTIVITY=

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD /healthcheck/index.sh

ENTRYPOINT ["/entrypoint.sh"]
