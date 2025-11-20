#!/bin/bash
################################################################################
# OpenSearch Setup Script
# Purpose: Configure index templates and ingest pipelines
################################################################################

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

OPENSEARCH_URL="${OPENSEARCH_URL:-http://localhost:9200}"
MAX_RETRIES=30
RETRY_DELAY=5

echo -e "${GREEN}=== OpenSearch Setup ===${NC}"
echo "Waiting for OpenSearch to be ready..."

# Wait for OpenSearch to be available
for i in $(seq 1 $MAX_RETRIES); do
    if curl -sf "${OPENSEARCH_URL}/_cluster/health" > /dev/null 2>&1; then
        echo -e "${GREEN}OpenSearch is ready!${NC}"
        break
    fi

    if [ $i -eq $MAX_RETRIES ]; then
        echo -e "${RED}Error: OpenSearch not available after ${MAX_RETRIES} retries${NC}"
        exit 1
    fi

    echo "Attempt $i/$MAX_RETRIES - waiting ${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
done

# Create GeoIP ingest pipeline
echo -e "${YELLOW}Creating GeoIP ingest pipeline...${NC}"
curl -X PUT "${OPENSEARCH_URL}/_ingest/pipeline/geoip-enrichment" \
  -H 'Content-Type: application/json' \
  -d @/home/user/honeypot/opensearch/index-templates/geoip-pipeline.json

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ GeoIP pipeline created${NC}"
else
    echo -e "${RED}✗ Failed to create GeoIP pipeline${NC}"
fi

# Create index template
echo -e "${YELLOW}Creating honeypot index template...${NC}"
curl -X PUT "${OPENSEARCH_URL}/_index_template/honeypot-template" \
  -H 'Content-Type: application/json' \
  -d @/home/user/honeypot/opensearch/index-templates/honeypot-template.json

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Index template created${NC}"
else
    echo -e "${RED}✗ Failed to create index template${NC}"
fi

# Verify setup
echo -e "${YELLOW}Verifying configuration...${NC}"
echo ""
echo "Cluster health:"
curl -s "${OPENSEARCH_URL}/_cluster/health?pretty" | grep -E "(status|number_of_nodes)"
echo ""
echo "Index templates:"
curl -s "${OPENSEARCH_URL}/_index_template/honeypot-template" | grep -o '"name":"[^"]*"' || echo "Template not found"
echo ""
echo "Ingest pipelines:"
curl -s "${OPENSEARCH_URL}/_ingest/pipeline/geoip-enrichment" | grep -o '"description":"[^"]*"' || echo "Pipeline not found"

echo ""
echo -e "${GREEN}OpenSearch setup complete!${NC}"
echo "Access OpenSearch Dashboards at: http://localhost:5601"
