# Networking & Host Connectivity

Guide to networking issues between host and WARP containers.

## Architecture

```
Host Network
    │
    ├── Container Network (docker0)
    │       │
    │       └── CloudflareWARP (tun interface)
    │               │
    │               └── Cloudflare Edge
    │
    └── Host WARP (if installed)
            │
            └── Cloudflare Edge
```

## Common Issues

### 1. Host Cannot Reach Container

**Symptoms:**
- `curl --socks5-hostname 127.0.0.1:1080` fails from host
- Same command works inside container

**Root Cause:** Host WARP intercepting traffic to Docker network.

**Solutions:**

#### Solution A: Stop Host WARP

```bash
# macOS
sudo launchctl stop com.cloudflare.WarpMac

# Linux
sudo systemctl stop warp-svc
```

#### Solution B: Add Docker to Split Tunnel

Go to Cloudflare Zero Trust portal:
1. Navigate to Networks → Split Tunnels
2. Add Docker subnet (e.g., `172.16.0.0/12`)
3. Set to "Exclude" mode

#### Solution C: Use BETA_FIX_HOST_CONNECTIVITY

```yaml
environment:
  - BETA_FIX_HOST_CONNECTIVITY=1
```

This automatically adds routing rules. **Warning:** May conflict with intranet.

#### Solution D: Manual Routing

```bash
# Get Docker subnet
SUBNET=$(docker network inspect bridge | jq -r '.[0].IPAM.Config[0].Subnet')
echo $SUBNET  # e.g., 172.17.0.0/16

# Add nftables rules (inside container)
docker exec warp-test sudo nft add table inet cloudflare-warp
docker exec warp-test sudo nft add chain inet cloudflare-warp input '{ type filter hook input priority 0; policy accept; }'
docker exec warp-test sudo nft add chain inet cloudflare-warp output '{ type filter hook output priority 0; policy accept; }'
docker exec warp-test sudo nft add rule inet cloudflare-warp input ip saddr $SUBNET accept
docker exec warp-test sudo nft add rule inet cloudflare-warp output ip daddr $SUBNET accept

# Add routing rule
docker exec warp-test sudo ip rule add to $SUBNET lookup main priority 10
```

### 2. Container Cannot Reach Internet

**Symptoms:**
- `curl https://example.com` fails inside container
- WARP status shows "Connected"

**Check:**
```bash
# Test without proxy
docker exec warp-test curl -s https://1.1.1.1

# Test with proxy
docker exec warp-test curl -s --socks5 127.0.0.1:1080 https://1.1.1.1

# Check routing
docker exec warp-test ip route show
docker exec warp-test ip route show table 65743
```

**Solutions:**

1. Check DNS:
   ```bash
   docker exec warp-test cat /etc/resolv.conf
   docker exec warp-test nslookup cloudflare.com
   ```

2. Restart WARP:
   ```bash
   docker exec warp-test warp-cli disconnect
   sleep 2
   docker exec warp-test warp-cli connect
   ```

3. Check firewall:
   ```bash
   docker exec warp-test sudo nft list ruleset
   ```

### 3. Intermittent Connectivity

**Symptoms:**
- Connection works sometimes, fails other times
- Latency varies widely

**Root Causes:**
- Cloudflare colo switching
- Network congestion
- MASQUE connection instability

**Solutions:**

1. Check colo:
   ```bash
   docker exec warp-test curl -s --socks5 127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace | grep colo
   ```

2. Force reconnection:
   ```bash
   docker exec warp-test warp-cli disconnect
   sleep 5
   docker exec warp-test warp-cli connect
   ```

3. Check packet loss:
   ```bash
   docker logs warp-test | grep "packet_loss\|loss_pct"
   ```

### 4. Multiple Containers Conflict

**Symptoms:**
- Both containers use same IP
- One container blocks other

**Root Cause:** Shared registration or network namespace.

**Solutions:**

1. Separate volumes:
   ```yaml
   volumes:
     - ./warp1-data:/var/lib/cloudflare-warp
   ```

2. Separate networks:
   ```yaml
   networks:
     warp1-net:
     warp2-net:
   ```

3. Different ports:
   ```yaml
   ports:
     - "1081:1080"  # Container 1
     - "1082:1080"  # Container 2
   ```

## Docker Network Configuration

### Bridge Network (Default)

```yaml
services:
  warp:
    # Uses default bridge network
    ports:
      - "1080:1080"
```

Characteristics:
- NAT between container and host
- Container gets IP from 172.17.0.0/16
- Port mapping required for host access

### Host Network

```yaml
services:
  warp:
    network_mode: host
    # No port mapping needed
    # Container shares host network
```

Characteristics:
- No NAT overhead
- Container uses host IP directly
- Port conflicts possible
- Less isolation

### Custom Bridge Network

```yaml
services:
  warp1:
    networks:
      - warpnet
  warp2:
    networks:
      - warpnet

networks:
  warpnet:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16
```

Characteristics:
- Better isolation
- Custom subnet control
- DNS resolution between services

## Firewall Rules

### Check Existing Rules

```bash
# nftables
docker exec warp-test sudo nft list ruleset

# iptables (legacy)
docker exec warp-test sudo iptables -L -n
```

### Common Rules Needed

Allow Docker subnet traffic:
```bash
docker exec warp-test sudo nft add rule inet cloudflare-warp input ip saddr 172.16.0.0/12 accept
docker exec warp-test sudo nft add rule inet cloudflare-warp output ip daddr 172.16.0.0/12 accept
```

Allow local traffic:
```bash
docker exec warp-test sudo nft add rule inet cloudflareWARP input ip saddr 127.0.0.0/8 accept
```

## DNS Configuration

### Check DNS Settings

```bash
docker exec warp-test cat /etc/resolv.conf
docker exec warp-test warp-cli settings list | grep dns
```

### WARP DNS

WARP configures its own DNS servers (127.0.2.2, 127.0.2.3).

### Custom DNS

Override with:
```yaml
dns:
  - 1.1.1.1
  - 8.8.8.8
```

## Performance Tuning

### Reduce Latency

1. Use WireGuard instead of MASQUE
2. Run container close to Cloudflare colo
3. Use host network mode

### Increase Throughput

1. Multiple containers with load balancer
2. Increase GOST connections
3. Use HTTP/2 proxy

### Memory Usage

Monitor with:
```bash
docker stats warp-test
```

Typical: 50-100MB per container

## Debugging Commands

```bash
# Network interfaces
docker exec warp-test ip addr show

# Routing table
docker exec warp-test ip route show
docker exec warp-test ip route show table 65743

# Connections
docker exec warp-test ss -tlnp

# DNS
docker exec warp-test cat /etc/resolv.conf
docker exec warp-test nslookup cloudflare.com

# Firewall
docker exec warp-test sudo nft list ruleset

# WARP status
docker exec warp-test warp-cli status
docker exec warp-test warp-cli settings list
```
