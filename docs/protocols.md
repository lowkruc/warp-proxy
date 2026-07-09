# WARP Protocols

Guide to WARP tunnel protocols and their behavior.

## Overview

WARP supports two tunnel protocols:

| Protocol | Transport | Firewall Resistance | Latency | Default |
|----------|-----------|---------------------|---------|---------|
| MASQUE | QUIC/UDP | High | Higher | Yes (consumer) |
| WireGuard | UDP | Medium | Lower | No |

## MASQUE Protocol

### What is MASQUE?

MASQUE is Cloudflare's newer protocol that uses HTTP/3 (QUIC) for tunneling. It's designed to be more resistant to firewall blocking.

### Enable MASQUE

```bash
docker exec -it warp-test bash
warp-cli tunnel protocol set MASQUE
warp-cli settings list  # Verify "WARP tunnel protocol: MASQUE"
```

### MASQUE Characteristics

- Uses UDP port 443 (same as HTTPS)
- HTTP/3 with HTTP/2 fallback
- Better firewall resistance
- Post-quantum support enabled by default
- May have higher latency than WireGuard

### MASQUE in Docker

MASQUE may have issues in Docker due to:
- QUIC connection handling
- UDP packet processing
- Multiple container conflicts

**Workaround:** If MASQUE causes connectivity check timeouts, wait for tunnel interface instead of "Connected" status.

### MASQUE Settings

```bash
# Check MASQUE settings
docker exec warp-test warp-cli settings list | grep -A 5 "MASQUE"
```

Output:
```
(not set)	MASQUE Protocol Settings: 
  HTTP Version: MASQUE (HTTP/3 with HTTP/2 fallback)
```

### Post-Quantum Support

MASQUE supports post-quantum key exchange:

```bash
# Check post-quantum status
docker exec warp-test warp-cli settings list | grep -i "post.quantum"
```

Default: `Enabled with downgrades`

## WireGuard Protocol

### What is WireGuard?

WireGuard is the original WARP tunnel protocol. It's faster but easier to detect/block.

### Enable WireGuard

```bash
docker exec -it warp-test bash
warp-cli tunnel protocol set WireGuard
warp-cli settings list  # Verify protocol change
```

### WireGuard Characteristics

- Uses custom UDP protocol
- Lower latency than MASQUE
- Easier for firewalls to detect
- No post-quantum support
- More stable in Docker environments

### WireGuard in Docker

WireGuard generally works better in Docker:
- Simpler connection handling
- Less UDP-related issues
- More predictable behavior

### Protocol Mismatch Warning

Cloudflare may override local protocol settings:

```
Settings and Registration mismatch on tunnel protocol. Falling back to registration protocol.
```

**Cause:** Network policy forces MASQUE, local setting is WireGuard.

**Solution:** Re-register with desired protocol:
```bash
warp-cli registration delete
warp-cli tunnel protocol set WireGuard
warp-cli registration new
```

## Protocol Detection

### Check Current Protocol

```bash
docker exec warp-test warp-cli settings list | grep protocol
```

### Check Registration Protocol

```bash
docker exec warp-test warp-cli registration show
```

### Check Active Tunnel

```bash
docker logs warp-test | grep -E "protocol|tunnel"
```

Look for:
```
start_tunnel_processing{protocol="masque"}
# or
start_tunnel_processing{protocol="wireguard"}
```

## Protocol Comparison

### Latency

| Protocol | Typical RTT | Best For |
|----------|-------------|----------|
| MASQUE | 20-50ms | Censored networks |
| WireGuard | 15-30ms | Normal networks |

### Packet Loss

| Protocol | Typical Loss | Recovery |
|----------|--------------|----------|
| MASQUE | 0-5% | QUIC handles retransmission |
| WireGuard | 0-2% | Standard UDP handling |

### Connection Setup

| Protocol | Setup Time | Time to Ready |
|----------|------------|---------------|
| MASQUE | 2-5s | 5-30s (connectivity check) |
| WireGuard | 1-3s | 3-15s (connectivity check) |

### Firewall Behavior

| Protocol | Port | Detection Difficulty |
|----------|------|----------------------|
| MASQUE | 443 | Hard (looks like HTTPS) |
| WireGuard | Custom | Easy (known signature) |

## Troubleshooting Protocol Issues

### MASQUE Connectivity Check Timeout

**Symptoms:**
- `warp-cli status` stuck at "Connecting"
- Logs: `Tunnel trace failed error=TimedOut`

**Solutions:**

1. Wait longer (up to 60s)
2. Check host WARP is disabled
3. Try WireGuard:
   ```bash
   warp-cli tunnel protocol set WireGuard
   ```

### WireGuard Blocked by Firewall

**Symptoms:**
- Connection fails immediately
- Logs: `Connection refused` or timeout

**Solutions:**

1. Switch to MASQUE:
   ```bash
   warp-cli tunnel protocol set MASQUE
   ```

2. Use proxy mode if available

### Protocol Not Changing

**Symptoms:**
- Setting protocol doesn't take effect
- Still using old protocol

**Root Cause:** Network policy override.

**Solution:** Re-register:
```bash
warp-cli registration delete
warp-cli tunnel protocol set <protocol>
warp-cli registration new
warp-cli connect
```

## Best Practices

### For Normal Networks

Use MASQUE (default):
- Better firewall resistance
- Works in most environments
- Post-quantum support

### For Docker Environments

Consider WireGuard:
- More stable in containers
- Less connectivity check issues
- Simpler debugging

### For Corporate Networks

Use MASQUE:
- Looks like regular HTTPS traffic
- Less likely to be blocked
- Can bypass most firewalls

### For Multiple Containers

- Use same protocol for all containers
- Ensure separate registrations
- Monitor for conflicts
