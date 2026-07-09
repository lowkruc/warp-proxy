# Troubleshooting Guide

Common issues and solutions for warp-docker.

## Quick Diagnostics

```bash
# Check container status
docker ps -a | grep warp

# Check WARP status
docker exec warp-test warp-cli status

# Check registration
docker exec warp-test warp-cli registration show

# Check protocol
docker exec warp-test warp-cli settings list | grep protocol

# Check tunnel interface
docker exec warp-test ip link show CloudflareWARP

# Check logs
docker logs warp-test --tail 50
```

## Issues

### 1. Container stuck at "Performing connectivity checks"

**Symptoms:**
- `warp-cli status` shows "Connecting" indefinitely
- Logs show: `Tunnel trace failed error=TimedOut`
- Logs show: `Connectivity checks failed, retrying`

**Root Causes:**

#### A. Host WARP client running

The most common cause. Host's WARP intercepts traffic to Cloudflare.

**Check:**
```bash
# macOS
ps aux | grep warp

# Linux
systemctl status warp-svc
```

**Solution:**
```bash
# macOS
sudo launchctl stop com.cloudflare.WarpMac

# Linux
sudo systemctl stop warp-svc
```

#### B. Firewall blocking UDP

MASQUE protocol uses QUIC (UDP). Some networks block UDP.

**Check:**
```bash
docker exec warp-test bash -c "echo test | timeout 2 nc -u -w1 1.1.1.1 53"
```

**Solution:** Allow UDP port 443 outbound, or use a network that allows UDP.

#### C. Docker network issues

Multiple containers may conflict on same network.

**Solution:** Use separate networks or ensure proper isolation.

### 2. "open tun" Operation not permitted

**Symptoms:**
- Container fails to start
- Logs show: `{ err: Os { code: 1, kind: PermissionDenied, message: "Operation not permitted" }, context: "open tun" }`

**Root Cause:** Docker/containerd removed tun/tap from default device rules.

**Solution:**
```yaml
device_cgroup_rules:
  - 'c 10:200 rwm'
```

### 3. Host cannot reach container SOCKS5

**Symptoms:**
- `curl --socks5-hostname 127.0.0.1:1080` works from inside container
- Same command fails from host

**Root Cause:** WARP intercepting traffic meant for Docker network.

**Solutions:**

#### A. Add Docker network to WARP split tunnel

Go to Cloudflare Zero Trust portal → Split Tunnels → Add `172.16.0.0/12`

#### B. Use BETA_FIX_HOST_CONNECTIVITY

```yaml
environment:
  - BETA_FIX_HOST_CONNECTIVITY=1
```

**Warning:** May conflict with intranet services.

#### C. Manual routing fix

```bash
# Get Docker subnet
SUBNET=$(docker network inspect bridge | jq -r '.[0].IPAM.Config[0].Subnet')

# Add nftables rules (inside container)
docker exec warp-test sudo nft add rule inet cloudflare-warp input ip saddr $SUBNET accept
docker exec warp-test sudo nft add rule inet cloudflare-warp output ip daddr $SUBNET accept
docker exec warp-test sudo ip rule add to $SUBNET lookup main priority 10
```

### 4. Multiple containers sharing registration

**Symptoms:**
- Both containers show same registration ID
- One connects, other stuck
- Intermittent failures

**Root Cause:** Containers sharing volume with `reg.json`.

**Solution:** Use separate volumes for each container.

```yaml
# Wrong
volumes:
  - ./data:/var/lib/cloudflare-warp  # Both use same

# Correct
services:
  warp1:
    volumes:
      - ./warp1-data:/var/lib/cloudflare-warp
  warp2:
    volumes:
      - ./warp2-data:/var/lib/cloudflare-warp
```

### 5. Proxy stops working after restart

**Root Cause:** Registration data lost (not persisted).

**Solution:** Mount volume to persist data.

```yaml
volumes:
  - ./data:/var/lib/cloudflare-warp
```

### 6. Connection reset by peer

**Symptoms:**
- Logs show: `dial tcp ... connection reset by peer`
- Intermittent failures

**Root Cause:** MASQUE/QUIC connection instability.

**Solution:** Wait and retry. May take 30-60 seconds to stabilize.

### 7. High latency (>200ms)

**Check:**
```bash
docker exec warp-test warp-cli settings list | grep protocol
```

**Root Cause:** MASQUE protocol may have higher latency than WireGuard.

**Solutions:**

1. Try different Cloudflare colo:
   ```bash
   docker exec warp-test warp-cli disconnect
   sleep 2
   docker exec warp-test warp-cli connect
   ```

2. Check tunnel stats:
   ```bash
   docker logs warp-test | grep "tunnel_stats"
   ```

### 8. DNS resolution failing inside container

**Check:**
```bash
docker exec warp-test cat /etc/resolv.conf
docker exec warp-test nslookup cloudflare.com
```

**Root Cause:** WARP DNS configuration not applied.

**Solution:**
```bash
docker exec warp-test warp-cli disconnect
sleep 1
docker exec warp-test warp-cli connect
```

### 9. WARP client not registering

**Symptoms:**
- `registration new` fails
- Logs show API errors

**Root Cause:** Network issues or rate limiting.

**Solutions:**

1. Check network connectivity:
   ```bash
   docker exec warp-test curl -s https://api.cloudflareclient.com
   ```

2. Wait and retry (rate limiting):
   ```bash
   sleep 30
   docker exec warp-test warp-cli registration new
   ```

3. Delete existing and re-register:
   ```bash
   docker exec warp-test warp-cli registration delete
   docker exec warp-test warp-cli registration new
   ```

### 10. QLog generating huge logs

**Symptoms:**
- Disk usage growing rapidly
- Logs filling up

**Solution:** Disable QLog (default behavior):
```yaml
# Default is disabled, no action needed
# Or explicitly:
environment:
  - DEBUG_ENABLE_QLOG=  # empty = disabled
```

### 11. Container using MASQUE when you want WireGuard

**Check:**
```bash
docker exec warp-test warp-cli settings list | grep protocol
```

**Root Cause:** Cloudflare network policy defaults to MASQUE.

**Attempt fix:**
```bash
docker exec warp-test warp-cli tunnel protocol set WireGuard
```

**Note:** Network policy may override. This is controlled by Cloudflare.

### 12. GOST not starting

**Check:**
```bash
docker exec warp-test ps aux | grep gost
docker exec warp-test ss -tlnp | grep 1080
```

**Root Cause:** Entry script error or GOST not installed.

**Solution:** Rebuild image:
```bash
docker build -t warp-proxy .
```

### 13. Container restarting repeatedly

**Check:**
```bash
docker logs warp-test --tail 100
docker inspect warp-test | jq '.[0].State'
```

**Root Cause:** Health check failing or crash loop.

**Solution:**
1. Check logs for specific error
2. Increase WARP_SLEEP if startup is slow:
   ```yaml
   environment:
     - WARP_SLEEP=5
   ```
3. Remove restart policy temporarily for debugging:
   ```yaml
   restart: "no"
   ```

### 14. IPv6 not working

**Check:**
```bash
docker exec warp-test curl -6 https://ifconfig.me
```

**Solution:** Ensure sysctl is set:
```yaml
sysctls:
  - net.ipv6.conf.all.disable_ipv6=0
```

### 15. Permission denied errors in logs

**Symptoms:**
- Logs show: `Failed to get path for client error="Failed to read /proc/xxx/exe: Permission denied"`

**Root Cause:** Container running as non-root user cannot read /proc.

**Impact:** Cosmetic only, does not affect functionality.

**Solution:** Can ignore, or run as root (not recommended).

## Performance Tuning

### Reduce Image Size

Use multi-stage build or Alpine-based image if available.

### Reduce Latency

1. Run containers close to Cloudflare colo
2. Use direct network connection (avoid NAT layers)
3. Consider WireGuard if MASQUE has issues

### Increase Throughput

1. Run multiple containers with load balancer
2. Use GOST forward chain for multiple connections
3. Increase connection limits in load balancer

## Debug Commands

```bash
# Full container info
docker inspect warp-test | jq '.[0]'

# WARP debug info
docker exec warp-test warp-cli settings list
docker exec warp-test warp-cli registration show
docker exec warp-test warp-cli status

# Network info
docker exec warp-test ip addr show
docker exec warp-test ip route show
docker exec warp-test ip route show table 65743

# Firewall rules
docker exec warp-test sudo nft list ruleset

# Connection test
docker exec warp-test curl -s --socks5 127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace
```

## Getting Help

1. Check container logs: `docker logs warp-test`
2. Check WARP status: `docker exec warp-test warp-cli status`
3. Search GitHub issues: https://github.com/cmj2002/warp-docker/issues
4. Create new issue with:
   - `docker logs warp-test` output
   - `docker inspect warp-test` output
   - `docker exec warp-test warp-cli status` output
   - Docker and OS versions
