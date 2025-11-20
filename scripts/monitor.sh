#!/bin/bash
################################################################################
# Honeypot Monitoring Script
# Purpose: Monitor honeypot activity and generate statistics
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

OPENSEARCH_URL="http://localhost:9200"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Honeypot Activity Monitor                          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if OpenSearch is available
if ! curl -sf "${OPENSEARCH_URL}/_cluster/health" > /dev/null 2>&1; then
    echo -e "${RED}Error: OpenSearch is not available${NC}"
    exit 1
fi

# Get time ranges
NOW=$(date +%s)000
HOUR_AGO=$((NOW - 3600000))
DAY_AGO=$((NOW - 86400000))
WEEK_AGO=$((NOW - 604800000))

# Function to query OpenSearch
query_opensearch() {
    local query=$1
    curl -s -X GET "${OPENSEARCH_URL}/honeypot-*/_search" \
        -H 'Content-Type: application/json' \
        -d "$query"
}

# Total Events
echo -e "${CYAN}=== Event Statistics ===${NC}"
TOTAL_EVENTS=$(query_opensearch '{"size":0,"track_total_hits":true}' | grep -o '"value":[0-9]*' | head -1 | cut -d: -f2)
echo -e "Total events captured: ${GREEN}${TOTAL_EVENTS:-0}${NC}"

# Events in last hour
EVENTS_HOUR=$(query_opensearch "{\"size\":0,\"query\":{\"range\":{\"@timestamp\":{\"gte\":$HOUR_AGO}}}}" | grep -o '"value":[0-9]*' | head -1 | cut -d: -f2)
echo -e "Events (last hour):    ${GREEN}${EVENTS_HOUR:-0}${NC}"

# Events in last 24h
EVENTS_DAY=$(query_opensearch "{\"size\":0,\"query\":{\"range\":{\"@timestamp\":{\"gte\":$DAY_AGO}}}}" | grep -o '"value":[0-9]*' | head -1 | cut -d: -f2)
echo -e "Events (last 24h):     ${GREEN}${EVENTS_DAY:-0}${NC}"

# Events in last 7d
EVENTS_WEEK=$(query_opensearch "{\"size\":0,\"query\":{\"range\":{\"@timestamp\":{\"gte\":$WEEK_AGO}}}}" | grep -o '"value":[0-9]*' | head -1 | cut -d: -f2)
echo -e "Events (last 7d):      ${GREEN}${EVENTS_WEEK:-0}${NC}"

echo ""
echo -e "${CYAN}=== Top 10 Source IPs ===${NC}"
TOP_IPS=$(query_opensearch '{"size":0,"aggs":{"top_ips":{"terms":{"field":"source.ip","size":10}}}}' 2>/dev/null)
if [ ! -z "$TOP_IPS" ]; then
    echo "$TOP_IPS" | grep -o '"key":"[^"]*","doc_count":[0-9]*' | head -10 | while read line; do
        IP=$(echo "$line" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
        COUNT=$(echo "$line" | grep -o '"doc_count":[0-9]*' | cut -d: -f2)
        printf "  %-20s ${GREEN}%6s${NC} events\n" "$IP" "$COUNT"
    done
else
    echo "  No data available"
fi

echo ""
echo -e "${CYAN}=== Top 10 Countries ===${NC}"
TOP_COUNTRIES=$(query_opensearch '{"size":0,"aggs":{"top_countries":{"terms":{"field":"source.geo.country_name.keyword","size":10}}}}' 2>/dev/null)
if [ ! -z "$TOP_COUNTRIES" ]; then
    echo "$TOP_COUNTRIES" | grep -o '"key":"[^"]*","doc_count":[0-9]*' | head -10 | while read line; do
        COUNTRY=$(echo "$line" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
        COUNT=$(echo "$line" | grep -o '"doc_count":[0-9]*' | cut -d: -f2)
        printf "  %-20s ${GREEN}%6s${NC} events\n" "$COUNTRY" "$COUNT"
    done
else
    echo "  No data available"
fi

echo ""
echo -e "${CYAN}=== Top 10 Usernames ===${NC}"
TOP_USERS=$(query_opensearch '{"size":0,"aggs":{"top_users":{"terms":{"field":"user.name","size":10}}}}' 2>/dev/null)
if [ ! -z "$TOP_USERS" ]; then
    echo "$TOP_USERS" | grep -o '"key":"[^"]*","doc_count":[0-9]*' | head -10 | while read line; do
        USER=$(echo "$line" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
        COUNT=$(echo "$line" | grep -o '"doc_count":[0-9]*' | cut -d: -f2)
        printf "  %-20s ${GREEN}%6s${NC} attempts\n" "$USER" "$COUNT"
    done
else
    echo "  No data available"
fi

echo ""
echo -e "${CYAN}=== Top 10 Passwords ===${NC}"
TOP_PASSWORDS=$(query_opensearch '{"size":0,"aggs":{"top_passwords":{"terms":{"field":"user.password","size":10}}}}' 2>/dev/null)
if [ ! -z "$TOP_PASSWORDS" ]; then
    echo "$TOP_PASSWORDS" | grep -o '"key":"[^"]*","doc_count":[0-9]*' | head -10 | while read line; do
        PASSWORD=$(echo "$line" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
        COUNT=$(echo "$line" | grep -o '"doc_count":[0-9]*' | cut -d: -f2)
        printf "  %-20s ${GREEN}%6s${NC} attempts\n" "$PASSWORD" "$COUNT"
    done
else
    echo "  No data available"
fi

echo ""
echo -e "${CYAN}=== Protocol Distribution ===${NC}"
PROTOCOL_DIST=$(query_opensearch '{"size":0,"aggs":{"protocols":{"terms":{"field":"honeypot"}}}}' 2>/dev/null)
if [ ! -z "$PROTOCOL_DIST" ]; then
    echo "$PROTOCOL_DIST" | grep -o '"key":"[^"]*","doc_count":[0-9]*' | while read line; do
        PROTOCOL=$(echo "$line" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)
        COUNT=$(echo "$line" | grep -o '"doc_count":[0-9]*' | cut -d: -f2)
        printf "  %-20s ${GREEN}%6s${NC} events\n" "$PROTOCOL" "$COUNT"
    done
else
    echo "  No data available"
fi

echo ""
echo -e "${CYAN}=== Container Status ===${NC}"
docker ps --filter "name=honeypot-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | while read line; do
    if echo "$line" | grep -q "Up"; then
        echo -e "${GREEN}$line${NC}"
    elif echo "$line" | grep -q "NAMES"; then
        echo -e "${YELLOW}$line${NC}"
    else
        echo -e "${RED}$line${NC}"
    fi
done

echo ""
echo -e "${CYAN}=== Disk Usage ===${NC}"
echo "Cowrie logs:     $(du -sh cowrie/logs 2>/dev/null | cut -f1 || echo '0B')"
echo "OpenCanary logs: $(du -sh logs/opencanary 2>/dev/null | cut -f1 || echo '0B')"

echo ""
echo -e "${CYAN}=== Recent Activity (Last 5 Events) ===${NC}"
RECENT=$(query_opensearch '{"size":5,"sort":[{"@timestamp":{"order":"desc"}}],"_source":["@timestamp","source.ip","eventid","user.name","input"]}' 2>/dev/null)
if [ ! -z "$RECENT" ]; then
    echo "$RECENT" | grep -o '"@timestamp":"[^"]*".*"source":{[^}]*}.*"eventid":"[^"]*"' | head -5 | while read line; do
        TIMESTAMP=$(echo "$line" | grep -o '"@timestamp":"[^"]*"' | cut -d'"' -f4 | cut -dT -f2 | cut -d. -f1)
        IP=$(echo "$line" | grep -o '"ip":"[^"]*"' | cut -d'"' -f4)
        EVENT=$(echo "$line" | grep -o '"eventid":"[^"]*"' | cut -d'"' -f4)
        echo -e "  ${YELLOW}$TIMESTAMP${NC} - ${CYAN}$IP${NC} - $EVENT"
    done
else
    echo "  No recent activity"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  For detailed analysis, visit http://localhost:5601       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
