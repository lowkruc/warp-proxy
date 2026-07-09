# Running Multiple Containers

Guide for running multiple WARP containers for load balancing or redundancy.

## Why Multiple Containers?

1. **Load balancing** - Distribute traffic across multiple WARP connections
2. **Redundancy** - If one container fails, others continue working
3. **Different configurations** - Run different protocols or settings per container
4. **IP rotation** - Each container gets different IP from Cloudflare

## Prerequisite: Separate Volumes

**CRITICAL:** Each container MUST have its own volume. Sharing causes registration conflicts.

### Wrong (Shared Volume)

```yaml
volumes:
  - ./data:/var/lib/cloudflare-warp  # Both containers use same data
```

Result:
- Container 1 connects successfully
- Container 2 stuck at "Performing connectivity checks"
- Both may fail intermittently

### Correct (Separate Volumes)

```yaml
services:
  warp1:
    volumes:
      - ./warp1-data:/var/lib/cloudflare-warp
  warp2:
    volumes:
      - ./warp2-data:/var/lib/cloudflare-warp
```

## Docker Compose Setup

### Two Containers with Separate Data

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
    networks:
      - warpnet

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
    networks:
      - warpnet

networks:
  warpnet:
    driver: bridge
```

### With HAProxy Load Balancer

```yaml
version: "3"

services:
  haproxy:
    image: haproxy:2.8-alpine
    container_name: haproxy
    restart: always
    ports:
      - "1080:1080"
    volumes:
      - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    depends_on:
      - warp1
      - warp2
    networks:
      - warpnet

  warp1:
    image: ghcr.io/lowkruc/warp-proxy:latest
    container_name: warp1
    restart: always
    device_cgroup_rules:
      - 'c 10:200 rwm'
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
    networks:
      - warpnet
    # No port mapping - HAProxy connects internally

  warp2:
    image: ghcr.io/lowkruc/warp-proxy:latest
    container_name: warp2
    restart: always
    device_cgroup_rules:
      - 'c 10:200 rwm'
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
    networks:
      - warpnet
    # No port mapping - HAProxy connects internally

networks:
  warpnet:
    driver: bridge
```

### HAProxy Configuration

Create `haproxy.cfg`:

```
global
    log stdout format raw local0
    maxconn 1000

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  30s
    timeout server  30s
    retries 3

frontend socks_front
    bind *:1080
    default_backend socks_back

backend socks_back
    balance roundrobin
    option tcp-check
    server warp1 warp1:1080 check inter 5s fall 3 rise 2
    server warp2 warp2:1080 check inter 5s fall 3 rise 2
```

### With Nginx Stream Module

```yaml
version: "3"

services:
  nginx:
    image: nginx:alpine
    container_name: nginx
    ports:
      - "1080:1080"
    volumes:
      - ./nginx-stream.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - warp1
      - warp2
    networks:
      - warpnet

  warp1:
    # ... same as above

  warp2:
    # ... same as above

networks:
  warpnet:
    driver: bridge
```

Create `nginx-stream.conf`:

```nginx
events {
    worker_connections 1024;
}

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

## Three or More Containers

```yaml
version: "3"

services:
  warp1:
    image: ghcr.io/lowkruc/warp-proxy:latest
    volumes:
      - ./warp1-data:/var/lib/cloudflare-warp
    # ...

  warp2:
    image: ghcr.io/lowkruc/warp-proxy:latest
    volumes:
      - ./warp2-data:/var/lib/cloudflare-warp
    # ...

  warp3:
    image: ghcr.io/lowkruc/warp-proxy:latest
    volumes:
      - ./warp3-data:/var/lib/cloudflare-warp
    # ...
```

Update HAProxy:

```
backend socks_back
    balance roundrobin
    server warp1 warp1:1080 check
    server warp2 warp2:1080 check
    server warp3 warp3:1080 check
```

## Verification

### Check Registration IDs (Must be Different)

```bash
docker exec warp1 warp-cli registration show | grep "ID:"
docker exec warp2 warp-cli registration show | grep "ID:"
```

Expected output:
```
ID: fc476747-e308-4823-ba47-de6b863fe6ab
ID: 5e15b723-08a6-415a-ae6f-d214c12f9b09
```

### Check IPs (Should be Different or Rotate)

```bash
for i in $(seq 1 10); do
  port=$((1081 + (i % 2)))
  ip=$(curl -s --socks5-hostname 127.0.0.1:$port https://cloudflare.com/cdn-cgi/trace | grep "^ip=" | cut -d= -f2)
  echo "Container $((i % 2 + 1)): $ip"
done
```

### Test Load Balancing

```bash
# Direct test each container
curl --socks5-hostname 127.0.0.1:1081 https://cloudflare.com/cdn-cgi/trace | grep warp=
curl --socks5-hostname 127.0.0.1:1082 https://cloudflare.com/cdn-cgi/trace | grep warp=

# Test through load balancer
curl --socks5-hostname 127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace | grep warp=
```

### Concurrent Test

```bash
for i in $(seq 1 20); do
  (curl -s --socks5-hostname 127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace | grep "^ip=") &
done
wait
```

## Common Issues

### One Container Stuck Connecting

**Cause:** Connectivity check timeout (MASQUE/UDP issues)

**Solution:** Wait and retry. MASQUE connections may take 30-60 seconds.

### Same IP from Both Containers

**Cause:** Same registration (shared volume)

**Solution:** Ensure separate volumes and re-register:
```bash
docker exec warp2 warp-cli registration delete
docker exec warp2 warp-cli registration new
docker exec warp2 warp-cli connect
```

### Load Balancer Not Distributing

**Check HAProxy stats:**
```bash
docker exec haproxy cat /var/log/haproxy.log
```

**Verify backends are up:**
```bash
docker exec warp1 warp-cli status
docker exec warp2 warp-cli status
```
