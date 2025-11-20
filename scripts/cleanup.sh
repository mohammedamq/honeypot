#!/bin/bash
################################################################################
# Honeypot Cleanup Script
# Purpose: Clean old logs and maintain system health
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

OPENSEARCH_URL="http://localhost:9200"
DAYS_TO_KEEP=${DAYS_TO_KEEP:-30}

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Honeypot Cleanup & Maintenance                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}This script will clean logs and data older than $DAYS_TO_KEEP days${NC}"
echo ""

# Get current sizes
echo -e "${GREEN}Current disk usage:${NC}"
echo "Cowrie logs:     $(du -sh cowrie/logs 2>/dev/null | cut -f1 || echo '0B')"
echo "OpenCanary logs: $(du -sh logs/opencanary 2>/dev/null | cut -f1 || echo '0B')"
echo "Cowrie data:     $(du -sh cowrie/data 2>/dev/null | cut -f1 || echo '0B')"
echo ""

read -p "Continue with cleanup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

# Backup current logs before cleanup
echo -e "${GREEN}Creating backup...${NC}"
BACKUP_FILE="honeypot-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "/tmp/$BACKUP_FILE" \
    cowrie/logs/*.json \
    logs/opencanary/*.json \
    2>/dev/null || true
echo -e "${GREEN}✓ Backup created: /tmp/$BACKUP_FILE${NC}"

# Clean old Cowrie logs
echo -e "${GREEN}Cleaning Cowrie logs...${NC}"
COWRIE_CLEANED=0
if [ -d "cowrie/logs" ]; then
    COWRIE_CLEANED=$(find cowrie/logs -name "*.log.*" -mtime +$DAYS_TO_KEEP -type f 2>/dev/null | wc -l)
    find cowrie/logs -name "*.log.*" -mtime +$DAYS_TO_KEEP -type f -delete 2>/dev/null || true
    find cowrie/logs -name "*.json.gz" -mtime +$DAYS_TO_KEEP -type f -delete 2>/dev/null || true
fi
echo -e "${GREEN}✓ Removed $COWRIE_CLEANED old Cowrie log files${NC}"

# Clean old OpenCanary logs
echo -e "${GREEN}Cleaning OpenCanary logs...${NC}"
OPENCANARY_CLEANED=0
if [ -d "logs/opencanary" ]; then
    OPENCANARY_CLEANED=$(find logs/opencanary -name "*.log.*" -mtime +$DAYS_TO_KEEP -type f 2>/dev/null | wc -l)
    find logs/opencanary -name "*.log.*" -mtime +$DAYS_TO_KEEP -type f -delete 2>/dev/null || true
    find logs/opencanary -name "*.json.gz" -mtime +$DAYS_TO_KEEP -type f -delete 2>/dev/null || true
fi
echo -e "${GREEN}✓ Removed $OPENCANARY_CLEANED old OpenCanary log files${NC}"

# Clean old downloaded malware samples
echo -e "${GREEN}Cleaning old malware samples...${NC}"
MALWARE_CLEANED=0
if [ -d "cowrie/data/downloads" ]; then
    MALWARE_CLEANED=$(find cowrie/data/downloads -mtime +$DAYS_TO_KEEP -type f 2>/dev/null | wc -l)
    find cowrie/data/downloads -mtime +$DAYS_TO_KEEP -type f -delete 2>/dev/null || true
fi
echo -e "${GREEN}✓ Removed $MALWARE_CLEANED old malware samples${NC}"

# Clean old OpenSearch indices
echo -e "${GREEN}Cleaning old OpenSearch indices...${NC}"
if curl -sf "${OPENSEARCH_URL}/_cluster/health" > /dev/null 2>&1; then
    CUTOFF_DATE=$(date -d "$DAYS_TO_KEEP days ago" +%Y.%m.%d)
    INDICES_CLEANED=0

    # Get list of indices
    INDICES=$(curl -s "${OPENSEARCH_URL}/_cat/indices/honeypot-*?h=index" 2>/dev/null || echo "")

    if [ ! -z "$INDICES" ]; then
        for INDEX in $INDICES; do
            # Extract date from index name (assuming format: honeypot-YYYY.MM.DD)
            INDEX_DATE=$(echo "$INDEX" | grep -o '[0-9]\{4\}\.[0-9]\{2\}\.[0-9]\{2\}' || echo "")

            if [ ! -z "$INDEX_DATE" ]; then
                # Convert to comparable format
                INDEX_TIMESTAMP=$(date -d "${INDEX_DATE//./-}" +%s 2>/dev/null || echo "0")
                CUTOFF_TIMESTAMP=$(date -d "$DAYS_TO_KEEP days ago" +%s)

                if [ $INDEX_TIMESTAMP -lt $CUTOFF_TIMESTAMP ]; then
                    curl -X DELETE "${OPENSEARCH_URL}/${INDEX}" -s > /dev/null 2>&1
                    ((INDICES_CLEANED++))
                    echo "  Deleted index: $INDEX"
                fi
            fi
        done
    fi

    echo -e "${GREEN}✓ Removed $INDICES_CLEANED old OpenSearch indices${NC}"
else
    echo -e "${YELLOW}⚠ OpenSearch not available, skipping index cleanup${NC}"
fi

# Docker cleanup
echo -e "${GREEN}Cleaning Docker resources...${NC}"
docker system prune -f > /dev/null 2>&1 || true
echo -e "${GREEN}✓ Docker cleanup complete${NC}"

# Rotate current logs (compress old logs)
echo -e "${GREEN}Compressing current logs...${NC}"
find cowrie/logs -name "cowrie.json" -size +10M -exec gzip -c {} \; > /dev/null 2>&1 || true
find logs/opencanary -name "opencanary.json" -size +10M -exec gzip -c {} \; > /dev/null 2>&1 || true
echo -e "${GREEN}✓ Log compression complete${NC}"

# Final sizes
echo ""
echo -e "${GREEN}Final disk usage:${NC}"
echo "Cowrie logs:     $(du -sh cowrie/logs 2>/dev/null | cut -f1 || echo '0B')"
echo "OpenCanary logs: $(du -sh logs/opencanary 2>/dev/null | cut -f1 || echo '0B')"
echo "Cowrie data:     $(du -sh cowrie/data 2>/dev/null | cut -f1 || echo '0B')"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Cleanup Complete!                             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Summary:${NC}"
echo "  • Cowrie files removed:    $COWRIE_CLEANED"
echo "  • OpenCanary files removed: $OPENCANARY_CLEANED"
echo "  • Malware samples removed: $MALWARE_CLEANED"
echo "  • OpenSearch indices removed: ${INDICES_CLEANED:-0}"
echo "  • Backup location: /tmp/$BACKUP_FILE"
echo ""
echo -e "${YELLOW}Note: Keep the backup file safe. Remove it manually when no longer needed.${NC}"
