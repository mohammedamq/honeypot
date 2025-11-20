#!/bin/bash
################################################################################
# Honeypot Firewall Configuration Script
# Purpose: Secure honeypot deployment with strict outbound filtering
#
# Security Model:
# - Block ALL outbound traffic by default
# - Allow only DNS, NTP, and system updates
# - DNAT SSH (22→2222) and Telnet (23→2323) to Cowrie
# - Log all dropped packets for analysis
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

echo -e "${GREEN}=== Honeypot Firewall Setup ===${NC}"
echo "This will configure strict firewall rules for honeypot isolation"
echo ""

# Detect which firewall system to use
if command -v nft &> /dev/null; then
    FIREWALL="nftables"
    echo -e "${GREEN}Using nftables${NC}"
elif command -v iptables &> /dev/null; then
    FIREWALL="iptables"
    echo -e "${GREEN}Using iptables${NC}"
else
    echo -e "${RED}Error: Neither nftables nor iptables found!${NC}"
    exit 1
fi

# Get primary network interface
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -z "$INTERFACE" ]; then
    echo -e "${RED}Error: Could not detect primary network interface${NC}"
    exit 1
fi
echo -e "Primary interface: ${YELLOW}${INTERFACE}${NC}"

################################################################################
# NFTABLES CONFIGURATION
################################################################################

if [ "$FIREWALL" = "nftables" ]; then
    echo -e "${GREEN}Configuring nftables rules...${NC}"

    # Flush existing rules
    nft flush ruleset

    # Create table
    nft add table inet honeypot_filter

    # INPUT chain - allow established, allow management SSH on non-standard port
    nft add chain inet honeypot_filter input '{ type filter hook input priority 0; policy drop; }'
    nft add rule inet honeypot_filter input ct state established,related accept
    nft add rule inet honeypot_filter input iif lo accept
    nft add rule inet honeypot_filter input icmp type echo-request limit rate 5/second accept
    nft add rule inet honeypot_filter input tcp dport 22 accept comment '"Management SSH"'
    nft add rule inet honeypot_filter input tcp dport 2222 accept comment '"Cowrie SSH"'
    nft add rule inet honeypot_filter input tcp dport 2323 accept comment '"Cowrie Telnet"'
    nft add rule inet honeypot_filter input tcp dport 8080 accept comment '"OpenCanary HTTP"'
    nft add rule inet honeypot_filter input tcp dport 5601 accept comment '"OpenSearch Dashboards"'
    nft add rule inet honeypot_filter input tcp dport 9200 accept comment '"OpenSearch API"'

    # OUTPUT chain - strict filtering
    nft add chain inet honeypot_filter output '{ type filter hook output priority 0; policy drop; }'
    nft add rule inet honeypot_filter output ct state established,related accept
    nft add rule inet honeypot_filter output oif lo accept

    # Allow DNS (UDP/TCP port 53)
    nft add rule inet honeypot_filter output udp dport 53 accept comment '"DNS"'
    nft add rule inet honeypot_filter output tcp dport 53 accept comment '"DNS over TCP"'

    # Allow NTP (UDP port 123)
    nft add rule inet honeypot_filter output udp dport 123 accept comment '"NTP"'

    # Allow HTTP/HTTPS for updates (to specific repos if desired)
    nft add rule inet honeypot_filter output tcp dport 80 accept comment '"HTTP updates"'
    nft add rule inet honeypot_filter output tcp dport 443 accept comment '"HTTPS updates"'

    # Allow Docker registry
    nft add rule inet honeypot_filter output tcp dport 5000 accept comment '"Docker Registry"'

    # FORWARD chain - block everything
    nft add chain inet honeypot_filter forward '{ type filter hook forward priority 0; policy drop; }'

    # NAT table for port redirection
    nft add table ip honeypot_nat
    nft add chain ip honeypot_nat prerouting '{ type nat hook prerouting priority -100; }'
    nft add chain ip honeypot_nat postrouting '{ type nat hook postrouting priority 100; }'

    # DNAT rules: Redirect standard ports to honeypot ports
    nft add rule ip honeypot_nat prerouting iif $INTERFACE tcp dport 22 dnat to :2222 comment '"SSH to Cowrie"'
    nft add rule ip honeypot_nat prerouting iif $INTERFACE tcp dport 23 dnat to :2323 comment '"Telnet to Cowrie"'
    nft add rule ip honeypot_nat prerouting iif $INTERFACE tcp dport 80 dnat to :8080 comment '"HTTP to OpenCanary"'

    # Log dropped outbound packets (for debugging)
    nft add rule inet honeypot_filter output limit rate 10/minute log prefix '"nft-drop-out: "' drop

    echo -e "${GREEN}nftables rules configured successfully${NC}"

    # Save rules
    if command -v nft &> /dev/null; then
        nft list ruleset > /etc/nftables.conf
        echo -e "${GREEN}Rules saved to /etc/nftables.conf${NC}"
    fi

################################################################################
# IPTABLES CONFIGURATION
################################################################################

elif [ "$FIREWALL" = "iptables" ]; then
    echo -e "${GREEN}Configuring iptables rules...${NC}"

    # Flush existing rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X

    # Default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP

    # INPUT chain - allow established and honeypot services
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 5/sec -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT -m comment --comment "Management SSH"
    iptables -A INPUT -p tcp --dport 2222 -j ACCEPT -m comment --comment "Cowrie SSH"
    iptables -A INPUT -p tcp --dport 2323 -j ACCEPT -m comment --comment "Cowrie Telnet"
    iptables -A INPUT -p tcp --dport 8080 -j ACCEPT -m comment --comment "OpenCanary HTTP"
    iptables -A INPUT -p tcp --dport 5601 -j ACCEPT -m comment --comment "OpenSearch Dashboards"
    iptables -A INPUT -p tcp --dport 9200 -j ACCEPT -m comment --comment "OpenSearch API"

    # OUTPUT chain - strict filtering
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow DNS
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT -m comment --comment "DNS"
    iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT -m comment --comment "DNS over TCP"

    # Allow NTP
    iptables -A OUTPUT -p udp --dport 123 -j ACCEPT -m comment --comment "NTP"

    # Allow HTTP/HTTPS for updates
    iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT -m comment --comment "HTTP updates"
    iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT -m comment --comment "HTTPS updates"

    # Allow Docker registry
    iptables -A OUTPUT -p tcp --dport 5000 -j ACCEPT -m comment --comment "Docker Registry"

    # NAT rules for port redirection
    iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 22 -j REDIRECT --to-port 2222
    iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 23 -j REDIRECT --to-port 2323
    iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 80 -j REDIRECT --to-port 8080

    # Log dropped outbound packets
    iptables -A OUTPUT -m limit --limit 10/min -j LOG --log-prefix "iptables-drop-out: " --log-level 4

    echo -e "${GREEN}iptables rules configured successfully${NC}"

    # Save rules
    if command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || iptables-save > /etc/iptables.rules
        echo -e "${GREEN}Rules saved${NC}"
    fi
fi

################################################################################
# VERIFICATION
################################################################################

echo ""
echo -e "${GREEN}=== Firewall Configuration Complete ===${NC}"
echo ""
echo -e "${YELLOW}Current Rules Summary:${NC}"
if [ "$FIREWALL" = "nftables" ]; then
    nft list ruleset | grep -E "(chain|accept|drop)" | head -20
else
    echo "INPUT chain:"
    iptables -L INPUT -n --line-numbers | head -10
    echo ""
    echo "OUTPUT chain:"
    iptables -L OUTPUT -n --line-numbers | head -10
fi

echo ""
echo -e "${GREEN}Security Status:${NC}"
echo "✓ Outbound traffic blocked by default"
echo "✓ DNS allowed (port 53)"
echo "✓ NTP allowed (port 123)"
echo "✓ HTTP/HTTPS allowed for updates (ports 80, 443)"
echo "✓ Port redirections active:"
echo "  - TCP 22 → 2222 (SSH to Cowrie)"
echo "  - TCP 23 → 2323 (Telnet to Cowrie)"
echo "  - TCP 80 → 8080 (HTTP to OpenCanary)"
echo ""
echo -e "${YELLOW}WARNING: Make sure you're connected via a management interface${NC}"
echo -e "${YELLOW}or this system has console access before disconnecting!${NC}"
