<div align="center">

# 🌐 warp-proxy

**Optimized Docker image for Cloudflare WARP with SOCKS5 proxy**

[![CI](https://github.com/lowkruc/warp-docker/actions/workflows/ci.yml/badge.svg)](https://github.com/lowkruc/warp-docker/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/lowkruc/warp-docker?color=blue&label=latest)](https://github.com/lowkruc/warp-docker/releases/latest)
[![Docker](https://img.shields.io/badge/docker-ghcr.io%2Flowkruc%2Fwarp--proxy-blue?logo=docker)](https://ghcr.io/lowkruc/warp-proxy)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL%20v3-red.svg)](LICENSE)
[![Image Size](https://img.shields.io/docker/image-size/lowkruc/warp-proxy/latest?label=image%20size)](https://github.com/lowkruc/warp-docker/pkgs/container/warp-proxy)

<br />

**Only 241MB** — 76% smaller than original WARP image

[Quick Start](#-quick-start) · [Features](#-features) · [Configuration](#-configuration) · [Multiple Instances](#-multiple-instances) · [Build](#-build) · [Docs](#-documentation) · [Support](#-support)

---

</div>

## 🚀 Quick Start

```bash
docker run -d \
  --name warp \
  --restart always \
  --device /dev/net/tun \
  --cap-add MKNOD \
  --cap-add AUDIT_WRITE \
  --cap-add NET_ADMIN \
  -p 1080:1080 \
  -e WARP_SLEEP=2 \
  -v warp-data:/var/lib/cloudflare-warp \
  ghcr.io/lowkruc/warp-proxy:latest
```

Verify:

```bash
curl --socks5-hostname localhost:1080 https://cloudflare.com/cdn-cgi/trace
```

Output should contain `warp=on` or `warp=plus`.

### Docker Compose

```yaml
services:
  warp:
    image: ghcr.io/lowkruc/warp-proxy:latest
    container_name: warp
    restart: always
    device_cgroup_rules:
      - 'c 10:200 rwm'
    ports:
      - "1080:1080"
    environment:
      - WARP_SLEEP=2
    cap_add:
      - MKNOD
      - AUDIT_WRITE
      - NET_ADMIN
    sysctls:
      - net.ipv6.conf.all.disable_ipv6=0
      - net.ipv4.conf.all.src_valid_mark=1
    volumes:
      - ./data:/var/lib/cloudflare-warp
```

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🪶 **Optimized** | Only 241MB — stripped binaries, minimal deps |
| 🔄 **Auto-Reconnect** | Configurable rotation interval for IP changes |
| 🧦 **SOCKS5 Proxy** | GOST-powered proxy layer |
| 🩺 **Health Check** | Built-in health endpoint |
| 🏷️ **WARP+ Support** | License key support for WARP+ |
| 🐳 **Multi-Arch** | Supports `linux/amd64` and `linux/arm64` |
| 🔒 **Security** | Runs as non-root user, minimal attack surface |
| ⚡ **Pure Binary** | No GUI deps — only warp-svc, warp-cli, warp-dex |

## 📋 Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `WARP_SLEEP` | `2` | Seconds to wait for WARP daemon startup |
| `GOST_ARGS` | `-L :1080` | GOST listen config |
| `WARP_LICENSE_KEY` | (empty) | WARP+ license key |
| `WARP_ROTATION_INTERVAL` | `0` | Auto-reconnect interval in minutes (`0`=disabled) |
| `REGISTER_WHEN_MDM_EXISTS` | (empty) | Force consumer registration even with mdm.xml |
| `BETA_FIX_HOST_CONNECTIVITY` | (empty) | Auto-fix host→container routing |

### WARP Rotation

```yaml
environment:
  - WARP_ROTATION_INTERVAL=60  # Rotate IP every 60 minutes
```

This periodically reconnects WARP to get a new IP — useful for bypassing rate limits.

## 🏗️ Architecture

```
Host ──SOCKS5:1080──▸ [Container]
                        ├─ GOST (proxy layer)
                        │    └─▸ warp-svc (WARP daemon)
                        │           └─▸ Cloudflare (WireGuard/MASQUE)
                        └─ /dev/net/tun
```

**Optimizations applied:**
- Multi-stage Docker build (GOST + keyring)
- Extract cloudflare-warp .deb directly (skip GUI deps)
- Strip debug symbols from binaries (~15MB saved)
- Remove udev, e2fsprogs, locale, terminfo
- debian:bookworm-slim base

## 🔄 Multiple Instances

Run multiple WARP containers for IP rotation:

```bash
# Start 3 instances
for i in 1 2 3; do
  docker run -d \
    --name warp-$i \
    --restart always \
    --device /dev/net/tun \
    --cap-add MKNOD --cap-add AUDIT_WRITE --cap-add NET_ADMIN \
    -p $((1080+i)):1080 \
    -v warp-$i:/var/lib/cloudflare-warp \
    ghcr.io/lowkruc/warp-proxy:latest
done
```

> See [Multiple Containers Guide](docs/multiple-containers.md) for full details.

## 🔀 With Warp Proxy Manager

For automatic scaling and load balancing:

```bash
cd ../warp-proxy-manager
docker compose up -d
```

The manager will auto-create and manage multiple warp-proxy containers.

## 🏷️ Image Tags

| Tag | Description |
|-----|-------------|
| `latest` | Latest stable build |
| `{WARP_VERSION}-{GOST_VERSION}` | Specific versions |
| `{WARP_VERSION}-{GOST_VERSION}-{SHA}` | Specific commit |

## 🛠️ Build

```bash
docker build \
  --build-arg GOST_VERSION=2.12.0 \
  --build-arg WARP_VERSION=test \
  -t warp-proxy .
```

Or use GitHub Actions — push to `master` or trigger manually.

### GitHub Actions Setup

1. Fork this repo
2. Enable GitHub Packages in repo settings
3. Done — uses `GITHUB_TOKEN` automatically

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [Complete Guide](docs/README.md) | Full documentation |
| [Multiple Containers](docs/multiple-containers.md) | Running multiple WARP instances |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and solutions |
| [Protocols](docs/protocols.md) | MASQUE vs WireGuard |
| [Networking](docs/networking.md) | Host connectivity & network config |

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](../warp-proxy-manager/CONTRIBUTING.md).

## 📜 License

[GPL-3.0](LICENSE)

---

<div align="center">

## 💖 Support

If you find this project useful, consider supporting its development:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/lowkruc)
[![GitHub Sponsors](https://img.shields.io/badge/GitHub%20Sponsors-ea4aaa?style=for-the-badge&logo=github-sponsors&logoColor=white)](https://github.com/sponsors/lowkruc)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/lowkruc)

<br />

**Made with ❤️ by [lowkruc](https://github.com/lowkruc)**

[⬆ Back to top](#-warp-proxy)

</div>
