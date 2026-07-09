#!/bin/bash

# exit when any command fails
set -e

interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)

# if CloudflareWARP not started, abort
if [[ ! "$interfaces" =~ "CloudflareWARP" ]]; then
    echo "[fix-host-connectivity] CloudflareWARP not started, skip."
    exit 0
fi

# get excluded networks
networks=$(ip -4 -o addr show | awk '{for(i=1;i<=NF;i++) if($i ~ /^inet$/) print $(i+1)}' | grep -v '\.lo$' | grep -v 'CloudflareWARP' | while read cidr; do
  addr=${cidr%%/*}
  prefix=${cidr##*/}
  # convert prefix to mask and calculate network
  mask=$((0xFFFFFFFF << (32 - prefix) & 0xFFFFFFFF))
  IFS='.' read -r a b c d <<< "$addr"
  ip_num=$(( (a << 24) + (b << 16) + (c << 8) + d ))
  net_num=$((ip_num & mask))
  printf '%d.%d.%d.%d/%s\n' $(( (net_num >> 24) & 0xFF )) $(( (net_num >> 16) & 0xFF )) $(( (net_num >> 8) & 0xFF )) $((net_num & 0xFF)) "$prefix"
done)

# if no networks found, abort
if [ -z "$networks" ]; then
    echo "[fix-host-connectivity] WARNING: No networks found, abort."
    exit 0
fi

# add excluded networks to nft table cloudflare-warp and routing table
for network in $networks; do
  if ! sudo nft list table inet cloudflare-warp | grep -q "saddr $network accept"; then
    echo "[fix-host-connectivity] Adding $network to input chain of nft table cloudflare-warp ."
    sudo nft add rule inet cloudflare-warp input ip saddr $network accept
  fi
  if ! sudo nft list table inet cloudflare-warp | grep -q "daddr $network accept"; then
    echo "[fix-host-connectivity] Adding $network to output chain of nft table cloudflare-warp ."
    sudo nft add rule inet cloudflare-warp output ip daddr $network accept
  fi
  if ! ip rule list | grep -q "$network lookup main"; then
    # stop packet from using routing table created by CloudflareWARP
    echo "[fix-host-connectivity] Adding routing rule for $network."
    sudo ip rule add to $network lookup main priority 10
  fi
done
