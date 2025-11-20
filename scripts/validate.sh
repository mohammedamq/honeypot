#!/bin/bash
################################################################################
# Honeypot Validation Script
# Purpose: Validate honeypot deployment and connectivity
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Honeypot Validation & Testing                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to test service
test_service() {
    local name=$1
    local test_cmd=$2

    echo -n "Testing $name... "
    if eval "$test_cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test OpenSearch
echo -e "${YELLOW}[1] OpenSearch Services${NC}"
test_service "OpenSearch API" "curl -sf http://localhost:9200/_cluster/health"
test_service "OpenSearch Dashboards" "curl -sf http://localhost:5601/api/status"

# Test Honeypot Services
echo ""
echo -e "${YELLOW}[2] Honeypot Services${NC}"
test_service "Cowrie SSH (port 2222)" "timeout 3 nc -z localhost 2222"
test_service "Cowrie Telnet (port 2323)" "timeout 3 nc -z localhost 2323"
test_service "OpenCanary HTTP (port 8080)" "curl -sf http://localhost:8080 -m 3"

# Test Docker containers
echo ""
echo -e "${YELLOW}[3] Docker Containers${NC}"
test_service "Cowrie container" "docker ps | grep -q honeypot-cowrie"
test_service "OpenCanary container" "docker ps | grep -q honeypot-opencanary"
test_service "OpenSearch container" "docker ps | grep -q honeypot-opensearch"
test_service "Filebeat container" "docker ps | grep -q honeypot-filebeat"

# Test log files
echo ""
echo -e "${YELLOW}[4] Log Files${NC}"
test_service "Cowrie log directory" "test -d ./cowrie/logs"
test_service "OpenCanary log directory" "test -d ./logs/opencanary"

# Test OpenSearch indices
echo ""
echo -e "${YELLOW}[5] OpenSearch Configuration${NC}"
test_service "Index template exists" "curl -sf http://localhost:9200/_index_template/honeypot-template | grep -q honeypot"
test_service "GeoIP pipeline exists" "curl -sf http://localhost:9200/_ingest/pipeline/geoip-enrichment | grep -q geoip"

# Interactive SSH test
echo ""
echo -e "${YELLOW}[6] Interactive Tests${NC}"
echo -e "${BLUE}Running SSH connection test...${NC}"
(sleep 1; echo "exit") | timeout 5 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p 2222 root@localhost 2>/dev/null && \
    echo -e "${GREEN}✓ SSH connection successful${NC}" || \
    echo -e "${YELLOW}⚠ SSH test inconclusive (expected, may need external test)${NC}"

# Check for data ingestion
echo ""
echo -e "${YELLOW}[7] Data Ingestion${NC}"
sleep 5
OPENSEARCH_URL="http://localhost:9200"
DOC_COUNT=$(curl -sf "${OPENSEARCH_URL}/honeypot-*/_count" 2>/dev/null | grep -o '"count":[0-9]*' | cut -d: -f2 || echo "0")

if [ "$DOC_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Documents in OpenSearch: $DOC_COUNT${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠ No documents yet (run validation after some attacks)${NC}"
fi

# Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Validation Summary                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All critical tests passed!${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Test from external host: nmap -p 22,23,80 <your-ip>"
    echo "  2. Try SSH login: ssh user@<your-ip> (will be logged)"
    echo "  3. Wait 24-48 hours for real attack traffic"
    echo "  4. Check OpenSearch Dashboards for incoming data"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some tests failed. Review logs:${NC}"
    echo "  docker logs honeypot-cowrie"
    echo "  docker logs honeypot-opencanary"
    echo "  docker logs honeypot-filebeat"
    echo "  docker logs honeypot-opensearch"
    echo ""
    exit 1
fi
