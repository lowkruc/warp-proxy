# warp-proxy

Run official [Cloudflare WARP](https://1.1.1.1/) client in Docker.

> **Optimized image** — only 241MB (76% smaller than original).

## Usage

### Start the container

```yaml
version: "3"

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
      # - WARP_LICENSE_KEY= # optional
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

Try it out:

```bash
curl --socks5-hostname 127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace
```

If output contains `warp=on` or `warp=plus`, it's working.

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `WARP_SLEEP` | `2` | Seconds to wait for WARP daemon startup |
| `GOST_ARGS` | `-L :1080` | GOST listen config |
| `WARP_LICENSE_KEY` | (empty) | WARP+ license key |
| `REGISTER_WHEN_MDM_EXISTS` | (empty) | Force consumer reg even with mdm.xml |
| `BETA_FIX_HOST_CONNECTIVITY` | (empty) | Auto-fix host→container routing |

### Image Tags

| Tag | Description |
|-----|-------------|
| `latest` | Latest build |
| `{WARP_VERSION}-{GOST_VERSION}` | Specific versions |
| `{WARP_VERSION}-{GOST_VERSION}-{COMMIT_SHA}` | Specific commit |

Image: `ghcr.io/lowkruc/warp-proxy`

## Build

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

## How It Works

```
Host ──SOCKS5:1080──▸ [Container]
                        ├─ GOST (proxy layer) ──▸ warp-svc (WARP daemon) ──▸ Cloudflare
                        └─ /dev/net/tun (WireGuard/MASQUE tunnel)
```

**Optimizations applied:**
- Multi-stage build (GOST + keyring)
- Extract cloudflare-warp .deb directly (skip GUI deps)
- Strip debug symbols from binaries
- Remove udev, e2fsprogs, locale, terminfo
- debian:bookworm-slim base

## License

[GPL-3.0](LICENSE)
