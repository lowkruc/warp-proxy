# Documentation

Complete documentation for warp-docker.

## Table of Contents

- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Configuration](#configuration)
- [Running Multiple Containers](#running-multiple-containers)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)

## Quick Start

### Single Container

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

```bash
docker compose up -d
curl --socks5-hostname 127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace
```

Output should show `warp=on`.

## Architecture

```
Host ──SOCKS5:1080──▸ [Container]
                        ├─ GOST (proxy) ──▸ warp-svc (WARP daemon) ──▸ Cloudflare
                        └─ CloudflareWARP interface (tunnel)
```

- **GOST**: SOCKS5/HTTP proxy, listens on port 1080
- **warp-svc**: Cloudflare WARP daemon, manages tunnel
- **CloudflareWARP**: Virtual network interface created by WARP

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WARP_SLEEP` | `2` | Seconds to wait for WARP daemon startup |
| `GOST_ARGS` | `-L :1080` | GOST listen configuration |
| `WARP_LICENSE_KEY` | (empty) | WARP+ license key |
| `REGISTER_WHEN_MDM_EXISTS` | (empty) | Force consumer registration even with mdm.xml |
| `BETA_FIX_HOST_CONNECTIVITY` | (empty) | Auto-fix host→container routing |
| `WARP_ROTATION_INTERVAL` | `0` | Auto-reconnect interval in minutes (0=disabled) |
| `WARP_ENABLE_NAT` | (empty) | Enable NAT mode for L3 traffic |
| `DEBUG_ENABLE_QLOG` | (empty) | Enable QUIC logging (generates large logs) |

### Ports

Default: `1080` (SOCKS5 + HTTP proxy)

Change with `GOST_ARGS`:
```yaml
environment:
  - GOST_ARGS=-L :8080
```

### Persistent Data

Mount `/var/lib/cloudflare-warp` to persist registration:

```yaml
volumes:
  - ./data:/var/lib/cloudflare-warp
```

Without persistence, container re-registers on restart.

## Running Multiple Containers

### Important: Separate Volumes Required

Each WARP container MUST have its own registration. Sharing volumes causes:

```
Container 1 ─┐
             ├──▸ Same registration ID ──▸ Cloudflare conflict
Container 2 ─┘
```

**Symptoms of shared registration:**
- One container connects, other stuck at "Performing connectivity checks"
- Intermittent connectivity failures
- Both containers may fail

### Correct Setup

```yaml
version: "3"

services:
  warp1:
    image: ghcr.io/lowkruc/warp-proxy:latest
    container_name: warp1
    restart: always
    device_cgroup_rules:
      - 'c 10:200 rwm'
    ports:
      - "1081:1080"
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
      - ./warp1-data:/var/lib/cloudflare-warp

  warp2:
    image: ghcr.io/lowkruc/warp-proxy:latest
    container_name: warp2
    restart: always
    device_cgroup_rules:
      - 'c 10:200 rwm'
    ports:
      - "1082:1080"
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
      - ./warp2-data:/var/lib/cloudflare-warp
```

### Alternative: Named Volumes (Ephemeral)

```yaml
version: "3"

services:
  warp1:
    image: ghcr.io/lowkruc/warp-proxy:latest
    container_name: warp1
    # ... (same config)
    volumes:
      - warpvol1:/var/lib/cloudflare-warp

  warp2:
    image: ghcr.io/lowkruc/warp-proxy:latest
    container_name: warp2
    # ... (same config)
    volumes:
      - warpvol2:/var/lib/cloudflare-warp

volumes:
  warpvol1:
  warpvol2:
```

Data is lost on container removal. Use for testing only.

### Load Balancing

#### Round-Robin with HAProxy

```yaml
version: "3"

services:
  haproxy:
    image: haproxy:latest
    container_name: haproxy
    ports:
      - "1080:1080"
    volumes:
      - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    depends_on:
      - warp1
      - warp2

  warp1:
    image: ghcr.io/lowkruc/warp-proxy:latest
    container_name: warp1
    # ... (config without port mapping)
    volumes:
      - warpvol1:/var/lib/cloudflare-warp

  warp2:
    image: ghcr.io/lowkruc/warp-proxy:latest
    container_name: warp2
    # ... (config without port mapping)
    volumes:
      - warpvol2:/var/lib/cloudflare-warp

volumes:
  warpvol1:
  warpvol2:
```

**haproxy.cfg:**
```
global
    log stdout format raw local0

defaults
    log     global
    mode    tcp
    option  tcplog
    timeout connect 5s
    timeout client  30s
    timeout server  30s

frontend socks_front
    bind *:1080
    default_backend socks_back

backend socks_back
    balance roundrobin
    server warp1 warp1:1080 check
    server warp2 warp2:1080 check
```

#### Round-Robin with Nginx (Stream Module)

```nginx
stream {
    upstream warp_backend {
        least_conn;
        server warp1:1080;
        server warp2:1080;
    }

    server {
        listen 1080;
        proxy_pass warp_backend;
        proxy_connect_timeout 5s;
        proxy_timeout 30s;
    }
}
```

### Verify Multiple Containers

```bash
# Check each container
curl --socks5-hostname 127.0.0.1:1081 https://cloudflare.com/cdn-cgi/trace
curl --socks5-hostname 127.0.0.1:1082 https://cloudflare.com/cdn-cgi/trace

# Check registration IDs (should be different)
docker exec warp1 warp-cli registration show
docker exec warp2 warp-cli registration show

# Check IPs (should be different or rotate)
for i in $(seq 1 10); do
  port=$((1081 + (i % 2)))
  curl -s --socks5-hostname 127.0.0.1:$port https://cloudflare.com/cdn-cgi/trace | grep ip=
done
```

## Troubleshooting

### Issue: Container stuck at "Performing connectivity checks"

**Cause:** Connectivity check to `connectivity.cloudflareclient.com` times out.

**Common reasons:**
1. Host WARP client running (intercepts traffic)
2. UDP/QUIC blocked by firewall
3. MASQUE protocol issues in Docker

**Solutions:**

1. **Stop host WARP client:**
   ```bash
   # macOS
   sudo launchctl stop com.cloudflare.WarpMac
   
   # Linux
   sudo systemctl stop warp-svc
   ```

2. **Check from inside container:**
   ```bash
   docker exec warp-test warp-cli status
   docker exec warp-test curl --socks5 127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace
   ```

3. **Check logs:**
   ```bash
   docker logs warp-test | grep -E "Connected|error|timeout"
   ```

### Issue: "open tun" Operation not permitted

**Cause:** Docker/runc removed tun/tap from default device rules.

**Solution:** Add device_cgroup_rules:
```yaml
device_cgroup_rules:
  - 'c 10:200 rwm'
```

### Issue: Host cannot reach container SOCKS5

**Cause:** WARP intercepting traffic meant for container.

**Solutions:**

1. **Add Docker network to WARP split tunnel:**
   - Go to Cloudflare Zero Trust portal
   - Add Docker subnet (e.g., `172.16.0.0/12`) to excluded routes

2. **Use BETA_FIX_HOST_CONNECTIVITY:**
   ```yaml
   environment:
     - BETA_FIX_HOST_CONNECTIVITY=1
   ```
   Warning: May conflict with intranet services.

3. **Manual routing fix:**
   ```bash
   # Get Docker network subnet
   docker network inspect bridge | grep Subnet
   
   # Add nftables rule (inside container)
   sudo nft add rule inet cloudflare-warp input ip saddr <subnet> accept
   sudo nft add rule inet cloudflare-warp output ip daddr <subnet> accept
   sudo ip rule add to <subnet> lookup main priority 10
   ```

### Issue: Proxy not working after container restart

**Cause:** Registration data lost (if not persisted).

**Solution:** Mount volume:
```yaml
volumes:
  - ./data:/var/lib/cloudflare-warp
```

Or re-register:
```bash
docker exec warp-test warp-cli registration new
docker exec warp-test warp-cli connect
```

### Issue: Connection reset by peer

**Cause:** MASQUE/QUIC connection issues.

**Check:**
```bash
docker logs warp-test | grep -E "quiche|QUIC|timeout"
```

**Solution:** Wait and retry. MASQUE connections may take longer to establish.

### Issue: Different protocols (WireGuard vs MASQUE)

**Observation:** Cloudflare now defaults to MASQUE for consumer accounts.

**Check protocol:**
```bash
docker exec warp-test warp-cli settings list | grep protocol
```

**Override (may not work due to network policy):**
```bash
docker exec warp-test warp-cli tunnel protocol set WireGuard
```

Note: Network policy from Cloudflare may override local settings.

### Issue: High latency or packet loss

**Check tunnel stats:**
```bash
docker logs warp-test | grep -E "tunnel_stats|packet"
```

**Common causes:**
- Network congestion
- UDP packet loss (MASQUE)
- Server location far from container

**Solution:** Try different Cloudflare colo by reconnecting:
```bash
docker exec warp-test warp-cli disconnect
sleep 2
docker exec warp-test warp-cli connect
```

### Issue: DNS resolution failing inside container

**Check DNS:**
```bash
docker exec warp-test cat /etc/resolv.conf
docker exec warp-test nslookup cloudflare.com
```

**Solution:** WARP should configure DNS automatically. If not:
```bash
docker exec warp-test warp-cli disconnect
sleep 1
docker exec warp-test warp-cli connect
```

## Advanced Usage

### Proxy Mode

WARP can run in proxy mode (only proxy traffic, not tunnel all):

```bash
docker exec -it warp-test bash
warp-cli mode proxy
warp-cli proxy port 40000
```

Update GOST_ARGS:
```yaml
environment:
  - GOST_ARGS=-L :1080 -F=127.0.0.1:40000
```

### NAT Gateway

Route L3 traffic through WARP:

```yaml
environment:
  - WARP_ENABLE_NAT=1
sysctls:
  - net.ipv4.ip_forward=1
  - net.ipv6.conf.all.forwarding=1
  - net.ipv6.conf.all.accept_ra=2
```

### Zero Trust Integration

```bash
docker exec -it warp-test bash
warp-cli registration new <your-team-name>
# Follow enrollment link
warp-cli registration token <token-from-page-source>
warp-cli connect
```

### MASQUE Protocol

Enable MASQUE (more firewall-resistant):

```bash
docker exec -it warp-test bash
warp-cli tunnel protocol set MASQUE
warp-cli settings list  # Verify
```

### Health Check

Default health check runs every 15s:

```yaml
healthcheck:
  interval: 15s
  timeout: 5s
  start_period: 10s
  retries: 3
  test: ["CMD", "/healthcheck/index.sh"]
```

Custom health check for proxy mode:
```bash
#!/bin/bash
curl -fsS --socks5-hostname 127.0.0.1:1080 "https://cloudflare.com/cdn-cgi/trace" | grep -qE "warp=(plus|on)" || exit 1
```

### IP Rotation

Auto-rotate IP periodically:

```yaml
environment:
  - WARP_ROTATION_INTERVAL=30  # minutes
```

### Podman Compatibility

Add capabilities:
```yaml
cap_add:
  - MKNOD
  - AUDIT_WRITE
  - NET_ADMIN
```

### Debug Logging

Enable QUIC debug logs:
```yaml
environment:
  - DEBUG_ENABLE_QLOG=true
```

Note: Generates large log files.

## Performance Notes

- **Latency:** Typically 80-120ms to nearest Cloudflare colo
- **Throughput:** Limited by WARP free tier
- **Concurrent connections:** GOST handles multiple connections well
- **Memory:** ~50-100MB per container
- **Disk:** Minimal (registration data only)

## Security Notes

- WARP encrypts all traffic through Cloudflare
- SOCKS5 proxy is unauthenticated by default
- Use firewall to restrict access to proxy port
- Registration keys are in volume data - protect accordingly
