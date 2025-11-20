#!/bin/bash
################################################################################
# Honeypot Deployment Script
# Purpose: Deploy multi-protocol honeypot system
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Multi-Protocol Honeypot Deployment System             ║${NC}"
echo -e "${BLUE}║     Cowrie (SSH/Telnet) + OpenCanary (HTTP)               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root for firewall setup
if [[ $EUID -ne 0 ]]; then
   echo -e "${YELLOW}Warning: Not running as root. Firewall setup will be skipped.${NC}"
   echo -e "${YELLOW}Run with sudo if you want to configure firewall rules.${NC}"
   SETUP_FIREWALL=false
else
   SETUP_FIREWALL=true
fi

# Check prerequisites
echo -e "${GREEN}[1/7] Checking prerequisites...${NC}"
command -v docker >/dev/null 2>&1 || { echo -e "${RED}Error: docker is required but not installed.${NC}" >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || command -v docker compose >/dev/null 2>&1 || { echo -e "${RED}Error: docker-compose is required but not installed.${NC}" >&2; exit 1; }
echo -e "${GREEN}✓ Docker and Docker Compose are installed${NC}"

# Navigate to project directory
cd "$PROJECT_DIR"

# Stop any existing containers
echo -e "${GREEN}[2/7] Stopping existing containers...${NC}"
docker-compose down -v 2>/dev/null || docker compose down -v 2>/dev/null || true
echo -e "${GREEN}✓ Cleanup complete${NC}"

# Create necessary directories
echo -e "${GREEN}[3/7] Creating directories...${NC}"
mkdir -p cowrie/{data,logs} opencanary logs/opencanary opensearch/{dashboards,index-templates}
chmod -R 777 cowrie/logs logs/opencanary 2>/dev/null || true
echo -e "${GREEN}✓ Directories created${NC}"

# Setup firewall rules (if root)
if [ "$SETUP_FIREWALL" = true ]; then
    echo -e "${GREEN}[4/7] Configuring firewall rules...${NC}"
    read -p "Do you want to setup firewall rules? This will modify iptables/nftables (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        bash "$SCRIPT_DIR/firewall-setup.sh"
    else
        echo -e "${YELLOW}Skipping firewall setup${NC}"
    fi
else
    echo -e "${YELLOW}[4/7] Skipping firewall setup (not root)${NC}"
fi

# Start services
echo -e "${GREEN}[5/7] Starting honeypot services...${NC}"
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose up -d
else
    docker compose up -d
fi

# Wait for services to be healthy
echo -e "${GREEN}Waiting for services to start...${NC}"
sleep 10

# Check service status
echo -e "${GREEN}Service status:${NC}"
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose ps
else
    docker compose ps
fi

# Setup OpenSearch
echo -e "${GREEN}[6/7] Configuring OpenSearch...${NC}"
sleep 15  # Give OpenSearch more time to fully start
bash "$SCRIPT_DIR/setup-opensearch.sh"

# Validation
echo -e "${GREEN}[7/7] Running validation tests...${NC}"
bash "$SCRIPT_DIR/validate.sh"

# Final status
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Deployment Complete!                          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Access Points:${NC}"
echo -e "  • OpenSearch Dashboards: ${YELLOW}http://localhost:5601${NC}"
echo -e "  • OpenSearch API:        ${YELLOW}http://localhost:9200${NC}"
echo -e "  • Cowrie SSH:            ${YELLOW}localhost:2222${NC} (or port 22 with NAT)"
echo -e "  • Cowrie Telnet:         ${YELLOW}localhost:2323${NC} (or port 23 with NAT)"
echo -e "  • OpenCanary HTTP:       ${YELLOW}http://localhost:8080${NC} (or port 80 with NAT)"
echo ""
echo -e "${GREEN}Log Locations:${NC}"
echo -e "  • Cowrie logs:           ${YELLOW}./cowrie/logs/${NC}"
echo -e "  • OpenCanary logs:       ${YELLOW}./logs/opencanary/${NC}"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "  1. Open OpenSearch Dashboards at http://localhost:5601"
echo "  2. Create index pattern: honeypot-*"
echo "  3. Build dashboards using queries in opensearch/dashboards/dashboard-queries.md"
echo "  4. Test connectivity: ssh root@localhost -p 2222"
echo "  5. Monitor for 24-48 hours and review incoming attacks"
echo ""
echo -e "${YELLOW}Security Reminder:${NC}"
echo "  • Ensure firewall rules are properly configured"
echo "  • Monitor outbound traffic regularly"
echo "  • Review logs daily for the first week"
echo "  • Never expose the OpenSearch Dashboard port publicly"
echo ""
echo -e "${GREEN}To view logs in real-time:${NC}"
echo "  docker logs -f honeypot-cowrie"
echo "  docker logs -f honeypot-opencanary"
echo "  docker logs -f honeypot-filebeat"
echo ""
