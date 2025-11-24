# Step-by-Step Implementation Guide

A detailed walkthrough for deploying the Multi-Protocol Honeypot System from scratch.

---

## Table of Contents

1. [Phase 1: Environment Preparation](#phase-1-environment-preparation)
2. [Phase 2: Network Security Setup](#phase-2-network-security-setup)
3. [Phase 3: Deploy Honeypot Services](#phase-3-deploy-honeypot-services)
4. [Phase 4: Configure Logging Pipeline](#phase-4-configure-logging-pipeline)
5. [Phase 5: Build Dashboards](#phase-5-build-dashboards)
6. [Phase 6: Validation & Testing](#phase-6-validation--testing)
7. [Phase 7: Production Hardening](#phase-7-production-hardening)
8. [Phase 8: Ongoing Operations](#phase-8-ongoing-operations)

---

## Phase 1: Environment Preparation

### Step 1.1: Provision Linux VM

**Requirements:**
- OS: Ubuntu 22.04 LTS or Debian 12 (recommended)
- RAM: Minimum 4GB (8GB recommended)
- Disk: Minimum 40GB
- CPU: 2+ cores
- Network: Public IP or port forwarding capability

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install essential packages
sudo apt-get install -y \
    curl \
    wget \
    git \
    net-tools \
    iptables \
    nftables \
    ca-certificates \
    gnupg \
    lsb-release
```

### Step 1.2: Install Docker

```bash
# Remove old Docker versions (if any)
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker's official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

# Verify installation
docker --version
docker compose version
```

### Step 1.3: Clone the Repository

```bash
# Clone the honeypot repository
git clone <repository-url> ~/honeypot
cd ~/honeypot

# Verify files are present
ls -la
```

**Expected output:**
```
docker-compose.yml
docker-compose.prod.yml
README.md
QUICKSTART.md
cowrie/
opencanary/
filebeat/
opensearch/
scripts/
logs/
```

### Step 1.4: Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit environment variables (optional)
nano .env
```

**Key variables to consider:**
```bash
# Increase memory for production
OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g

# Set timezone
TZ=UTC
```

---

## Phase 2: Network Security Setup

### Step 2.1: Understand the Network Architecture

```
                    INTERNET
                        │
                        ▼
              ┌─────────────────┐
              │    FIREWALL     │
              │  (iptables/nft) │
              └────────┬────────┘
                       │
         ┌─────────────┼─────────────┐
         │             │             │
         ▼             ▼             ▼
    Port 22       Port 23       Port 80
    (DNAT)        (DNAT)        (DNAT)
         │             │             │
         ▼             ▼             ▼
    Port 2222     Port 2323     Port 8080
    (Cowrie)      (Cowrie)     (OpenCanary)
         │             │             │
         └─────────────┼─────────────┘
                       │
                       ▼
              ┌─────────────────┐
              │    FILEBEAT     │
              │  (Log Shipper)  │
              └────────┬────────┘
                       │
                       ▼
              ┌─────────────────┐
              │   OPENSEARCH    │
              │  (Log Storage)  │
              └─────────────────┘
```

### Step 2.2: Review Firewall Script

```bash
# Read the firewall script
cat scripts/firewall-setup.sh
```

**Key security rules implemented:**

| Direction | Default | Allowed |
|-----------|---------|---------|
| INPUT | DROP | SSH (22, 2222), Telnet (2323), HTTP (8080, 5601), OpenSearch (9200) |
| OUTPUT | DROP | DNS (53), NTP (123), HTTP/S (80, 443) |
| FORWARD | DROP | None |

### Step 2.3: Apply Firewall Rules

```bash
# Run firewall setup (requires root)
sudo bash scripts/firewall-setup.sh
```

**Interactive prompts:**
1. Script detects nftables or iptables automatically
2. Applies INPUT rules for honeypot services
3. Applies OUTPUT rules (strict whitelist)
4. Configures DNAT for port redirection
5. Saves rules for persistence

### Step 2.4: Verify Firewall Configuration

```bash
# For iptables
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v

# For nftables
sudo nft list ruleset
```

**Expected NAT rules:**
```
DNAT       tcp  --  *      *       0.0.0.0/0   0.0.0.0/0   tcp dpt:22 to:2222
DNAT       tcp  --  *      *       0.0.0.0/0   0.0.0.0/0   tcp dpt:23 to:2323
DNAT       tcp  --  *      *       0.0.0.0/0   0.0.0.0/0   tcp dpt:80 to:8080
```

### Step 2.5: Test Outbound Blocking

```bash
# This should FAIL (blocked by firewall)
curl -I https://example.com --connect-timeout 5

# This should WORK (DNS allowed)
nslookup google.com

# This should WORK (NTP allowed)
ntpdate -q pool.ntp.org
```

---

## Phase 3: Deploy Honeypot Services

### Step 3.1: Create Directory Structure

```bash
cd ~/honeypot

# Create required directories with proper permissions
mkdir -p cowrie/{data,logs}
mkdir -p logs/opencanary
mkdir -p opensearch/{dashboards,index-templates}

# Set permissions for log directories
chmod -R 777 cowrie/logs logs/opencanary
```

### Step 3.2: Review Docker Compose Configuration

```bash
# View the service definitions
cat docker-compose.yml
```

**Services defined:**

| Service | Image | Ports | Purpose |
|---------|-------|-------|---------|
| cowrie | cowrie/cowrie:latest | 2222, 2323 | SSH/Telnet honeypot |
| opencanary | thinkst/opencanary:latest | 8080 | HTTP honeypot |
| opensearch | opensearchproject/opensearch:2.11.0 | 9200, 9600 | Log storage |
| opensearch-dashboards | opensearchproject/opensearch-dashboards:2.11.0 | 5601 | Visualization |
| filebeat | docker.elastic.co/beats/filebeat:8.11.0 | - | Log shipping |

### Step 3.3: Start Docker Services

```bash
# Pull latest images
docker compose pull

# Start all services in background
docker compose up -d

# Wait for services to initialize
echo "Waiting for services to start..."
sleep 30
```

### Step 3.4: Verify Container Status

```bash
# Check all containers are running
docker compose ps
```

**Expected output:**
```
NAME                    STATUS              PORTS
honeypot-cowrie         Up X minutes        0.0.0.0:2222->2222/tcp, 0.0.0.0:2323->2323/tcp
honeypot-opencanary     Up X minutes        0.0.0.0:8080->8080/tcp
honeypot-opensearch     Up X minutes        0.0.0.0:9200->9200/tcp, 0.0.0.0:9600->9600/tcp
honeypot-dashboards     Up X minutes        0.0.0.0:5601->5601/tcp
honeypot-filebeat       Up X minutes
```

### Step 3.5: Check Container Logs

```bash
# Check Cowrie is accepting connections
docker logs honeypot-cowrie 2>&1 | tail -20

# Check OpenCanary is running
docker logs honeypot-opencanary 2>&1 | tail -20

# Check OpenSearch is healthy
docker logs honeypot-opensearch 2>&1 | tail -20

# Check Filebeat is shipping logs
docker logs honeypot-filebeat 2>&1 | tail -20
```

### Step 3.6: Test Service Connectivity

```bash
# Test Cowrie SSH
nc -zv localhost 2222

# Test Cowrie Telnet
nc -zv localhost 2323

# Test OpenCanary HTTP
curl -s http://localhost:8080 | head -20

# Test OpenSearch API
curl -s http://localhost:9200/_cluster/health?pretty

# Test OpenSearch Dashboards
curl -s http://localhost:5601/api/status | head -5
```

---

## Phase 4: Configure Logging Pipeline

### Step 4.1: Setup OpenSearch Index Template

```bash
# Wait for OpenSearch to be fully ready
until curl -sf http://localhost:9200/_cluster/health > /dev/null; do
    echo "Waiting for OpenSearch..."
    sleep 5
done
echo "OpenSearch is ready!"

# Run OpenSearch setup script
bash scripts/setup-opensearch.sh
```

### Step 4.2: Verify Index Template

```bash
# Check template was created
curl -s http://localhost:9200/_index_template/honeypot-template | jq .
```

**Expected response includes:**
```json
{
  "index_templates": [{
    "name": "honeypot-template",
    "index_template": {
      "index_patterns": ["honeypot-*"],
      ...
    }
  }]
}
```

### Step 4.3: Verify GeoIP Pipeline

```bash
# Check pipeline was created
curl -s http://localhost:9200/_ingest/pipeline/geoip-enrichment | jq .
```

**Expected response includes:**
```json
{
  "geoip-enrichment": {
    "description": "GeoIP enrichment pipeline for honeypot logs",
    "processors": [...]
  }
}
```

### Step 4.4: Generate Test Data

```bash
# Attempt SSH login to generate log entry
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p 2222 testuser@localhost << 'EOF'
testpassword
whoami
ls -la
exit
EOF

# Access HTTP honeypot
curl http://localhost:8080/admin
curl http://localhost:8080/wp-admin
curl http://localhost:8080/.env
```

### Step 4.5: Verify Data Ingestion

```bash
# Wait for Filebeat to process logs
sleep 10

# Check if documents are being indexed
curl -s http://localhost:9200/honeypot-*/_count | jq .

# View sample documents
curl -s "http://localhost:9200/honeypot-*/_search?size=3&pretty"
```

**Expected output:**
```json
{
  "count": 5,
  "_shards": {
    "total": 1,
    "successful": 1,
    "failed": 0
  }
}
```

---

## Phase 5: Build Dashboards

### Step 5.1: Access OpenSearch Dashboards

1. Open browser: `http://<your-server-ip>:5601`
2. Wait for initialization (first load may take 30-60 seconds)

### Step 5.2: Create Index Pattern

1. Navigate to: **Stack Management** → **Index Patterns**
2. Click **Create index pattern**
3. Enter pattern: `honeypot-*`
4. Click **Next step**
5. Select time field: `@timestamp`
6. Click **Create index pattern**

### Step 5.3: Explore Data (Discover)

1. Navigate to: **Discover**
2. Select index pattern: `honeypot-*`
3. Set time range: Last 24 hours
4. Explore available fields in left sidebar

**Key fields to examine:**
- `source.ip` - Attacker IP address
- `source.geo.country_name` - Geographic location
- `user.name` - Attempted username
- `user.password` - Attempted password
- `eventid` - Event type
- `input` - Commands executed

### Step 5.4: Create Visualizations

#### Visualization 1: Events Over Time
1. Navigate to: **Visualize** → **Create visualization**
2. Select: **Line**
3. Select index: `honeypot-*`
4. Y-axis: Count
5. X-axis: Date Histogram → `@timestamp` → Auto interval
6. Save as: "Honeypot Events Over Time"

#### Visualization 2: Top Source IPs
1. Create new visualization → **Data Table**
2. Metric: Count
3. Buckets → Add → Split rows
4. Aggregation: Terms
5. Field: `source.ip`
6. Size: 20
7. Save as: "Top Source IPs"

#### Visualization 3: Geographic Map
1. Create new visualization → **Coordinate Map**
2. Metric: Count
3. Buckets → Add → Geohash
4. Field: `source.geo.location`
5. Save as: "Attack Origins Map"

#### Visualization 4: Top Usernames
1. Create new visualization → **Tag Cloud**
2. Metric: Count
3. Buckets → Add → Tags
4. Field: `user.name`
5. Size: 50
6. Save as: "Top Usernames"

#### Visualization 5: Top Passwords
1. Create new visualization → **Data Table**
2. Metric: Count
3. Buckets → Split rows → Terms → `user.password`
4. Size: 30
5. Save as: "Top Passwords"

#### Visualization 6: Protocol Distribution
1. Create new visualization → **Pie Chart**
2. Metric: Count
3. Buckets → Split slices → Terms → `honeypot`
4. Save as: "Protocol Distribution"

### Step 5.5: Create Dashboard

1. Navigate to: **Dashboard** → **Create dashboard**
2. Click **Add** → Select all created visualizations
3. Arrange layout:

```
┌────────────────────────────────┬────────────────────────────────┐
│   Events Over Time             │   Attack Origins Map           │
│   (full width top)             │                                │
├────────────────────────────────┼────────────────────────────────┤
│   Top Source IPs               │   Protocol Distribution        │
│                                │                                │
├────────────────────────────────┼────────────────────────────────┤
│   Top Usernames                │   Top Passwords                │
│                                │                                │
└────────────────────────────────┴────────────────────────────────┘
```

4. Save dashboard as: "Honeypot Threat Intelligence"

### Step 5.6: Set Auto-Refresh

1. In dashboard view, click time picker (top right)
2. Set refresh interval: 30 seconds
3. Click **Start**

---

## Phase 6: Validation & Testing

### Step 6.1: Run Automated Validation

```bash
bash scripts/validate.sh
```

**Expected output:**
```
╔════════════════════════════════════════════════════════════╗
║          Honeypot Validation & Testing                     ║
╚════════════════════════════════════════════════════════════╝

[1] OpenSearch Services
Testing OpenSearch API... ✓ PASS
Testing OpenSearch Dashboards... ✓ PASS

[2] Honeypot Services
Testing Cowrie SSH (port 2222)... ✓ PASS
Testing Cowrie Telnet (port 2323)... ✓ PASS
Testing OpenCanary HTTP (port 8080)... ✓ PASS

...

Tests Passed: 12
Tests Failed: 0

✓ All critical tests passed!
```

### Step 6.2: External Port Scan Test

From a different machine (or use online port scanner):

```bash
# From external machine
nmap -p 22,23,80,8080,2222,2323 <honeypot-ip>
```

**Expected results:**
- Port 22: Open (redirects to Cowrie)
- Port 23: Open (redirects to Cowrie)
- Port 80: Open (redirects to OpenCanary)

### Step 6.3: SSH Login Test

```bash
# From external machine
ssh root@<honeypot-ip>
# Enter any password when prompted
# Try common commands: whoami, ls, cat /etc/passwd
```

### Step 6.4: Verify Logging

```bash
# Back on honeypot server
# Check Cowrie captured the session
tail -f cowrie/logs/cowrie.json
```

**Expected log entry:**
```json
{
  "eventid": "cowrie.login.success",
  "username": "root",
  "password": "password123",
  "src_ip": "x.x.x.x",
  "timestamp": "2024-xx-xxTxx:xx:xx.xxxxxxZ"
}
```

### Step 6.5: Check Dashboard

1. Open OpenSearch Dashboards
2. Navigate to your dashboard
3. Verify new events appear
4. Check GeoIP enrichment is working (country should be populated)

---

## Phase 7: Production Hardening

### Step 7.1: Use Production Docker Compose

```bash
# Stop current deployment
docker compose down

# Start with production configuration
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

**Production changes:**
- Resource limits on containers
- Increased OpenSearch memory
- Dashboards bound to localhost only
- Log rotation configured

### Step 7.2: Secure Dashboard Access

**Option A: SSH Tunnel (Recommended)**
```bash
# From your local machine
ssh -L 5601:localhost:5601 user@honeypot-server

# Then access: http://localhost:5601
```

**Option B: Nginx Reverse Proxy with Auth**
```bash
# Install nginx
sudo apt-get install -y nginx apache2-utils

# Create password file
sudo htpasswd -c /etc/nginx/.htpasswd admin

# Configure nginx
sudo nano /etc/nginx/sites-available/dashboards
```

```nginx
server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        auth_basic "Honeypot Dashboard";
        auth_basic_user_file /etc/nginx/.htpasswd;
        proxy_pass http://127.0.0.1:5601;
    }
}
```

### Step 7.3: Configure Log Rotation

```bash
# Create logrotate configuration
sudo nano /etc/logrotate.d/honeypot
```

```
/home/user/honeypot/cowrie/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
}

/home/user/honeypot/logs/opencanary/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
}
```

### Step 7.4: Setup Automated Cleanup

```bash
# Add to crontab
crontab -e
```

```cron
# Run cleanup weekly (Sunday at 2 AM)
0 2 * * 0 cd /home/user/honeypot && DAYS_TO_KEEP=30 bash scripts/cleanup.sh >> /var/log/honeypot-cleanup.log 2>&1

# Run monitoring daily (email summary)
0 8 * * * cd /home/user/honeypot && bash scripts/monitor.sh | mail -s "Honeypot Daily Report" admin@example.com
```

### Step 7.5: Setup Alerts (Optional)

Create alerting rules in OpenSearch:

1. Navigate to: **Alerting** → **Monitors** → **Create monitor**
2. Configure trigger for high-volume attacks:
   - Query: Count events in last hour
   - Threshold: > 1000 events
   - Action: Send email notification

---

## Phase 8: Ongoing Operations

### Step 8.1: Daily Monitoring Routine

```bash
# Morning check
bash scripts/monitor.sh

# Check container health
docker compose ps

# Review recent high-value events
curl -s "http://localhost:9200/honeypot-*/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 10,
    "sort": [{"@timestamp": "desc"}],
    "query": {
      "bool": {
        "should": [
          {"term": {"eventid": "cowrie.session.file_download"}},
          {"term": {"eventid": "cowrie.command.input"}}
        ]
      }
    }
  }' | jq '.hits.hits[]._source'
```

### Step 8.2: Weekly TI Report Generation

```bash
# Run weekly summary query
curl -s "http://localhost:9200/honeypot-*/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "query": {
      "range": {
        "@timestamp": {"gte": "now-7d"}
      }
    },
    "aggs": {
      "total_events": {"value_count": {"field": "@timestamp"}},
      "unique_ips": {"cardinality": {"field": "source.ip"}},
      "top_countries": {"terms": {"field": "source.geo.country_name.keyword", "size": 10}},
      "top_usernames": {"terms": {"field": "user.name", "size": 20}},
      "top_passwords": {"terms": {"field": "user.password", "size": 20}}
    }
  }' | jq '.aggregations'
```

### Step 8.3: Incident Response

When investigating specific attacks:

```bash
# Find all events from specific IP
curl -s "http://localhost:9200/honeypot-*/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "term": {"source.ip": "x.x.x.x"}
    },
    "sort": [{"@timestamp": "asc"}]
  }' | jq '.hits.hits[]._source'

# Export session data
curl -s "http://localhost:9200/honeypot-*/_search?size=1000" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "term": {"session": "session-id-here"}
    }
  }' > incident-export.json
```

### Step 8.4: System Maintenance

```bash
# Weekly maintenance tasks
# 1. Update Docker images
docker compose pull
docker compose up -d

# 2. Clean old data
bash scripts/cleanup.sh

# 3. Backup important data
tar -czf ~/honeypot-backup-$(date +%Y%m%d).tar.gz \
    cowrie/logs/*.json \
    logs/opencanary/*.json

# 4. Check disk space
df -h
du -sh cowrie/logs logs/opencanary

# 5. Review firewall rules
sudo iptables -L -n -v | head -30
```

### Step 8.5: Scaling & Enhancement

**Add more protocols:**
```bash
# Edit opencanary.conf to enable more services
nano opencanary/opencanary.conf

# Enable FTP, MySQL, etc.
{
  "ftp.enabled": true,
  "ftp.port": 21,
  "mysql.enabled": true,
  "mysql.port": 3306
}

# Restart OpenCanary
docker compose restart opencanary
```

**Add threat feed correlation:**
```bash
# Download threat feeds
wget -O /tmp/known-bad-ips.txt https://example.com/threat-feed.txt

# Query for matches
while read ip; do
    curl -s "http://localhost:9200/honeypot-*/_count" \
      -H 'Content-Type: application/json' \
      -d "{\"query\":{\"term\":{\"source.ip\":\"$ip\"}}}"
done < /tmp/known-bad-ips.txt
```

---

## Troubleshooting Reference

### Common Issues

| Problem | Solution |
|---------|----------|
| Containers won't start | Check logs: `docker compose logs` |
| No data in OpenSearch | Verify Filebeat: `docker logs honeypot-filebeat` |
| Can't access dashboards | Check port binding: `netstat -tlnp \| grep 5601` |
| GeoIP not working | Verify pipeline: `curl localhost:9200/_ingest/pipeline/geoip-enrichment` |
| Firewall blocking SSH | Add management port: `iptables -A INPUT -p tcp --dport 22 -j ACCEPT` |
| Disk filling up | Run cleanup: `bash scripts/cleanup.sh` |

### Useful Commands Cheatsheet

```bash
# Service management
docker compose up -d          # Start services
docker compose down           # Stop services
docker compose restart        # Restart all
docker compose logs -f        # Follow logs

# Monitoring
bash scripts/monitor.sh       # Activity dashboard
bash scripts/validate.sh      # System check

# Maintenance
bash scripts/cleanup.sh       # Clean old data

# OpenSearch queries
curl localhost:9200/_cat/indices?v           # List indices
curl localhost:9200/honeypot-*/_count        # Count documents
curl localhost:9200/_cluster/health?pretty   # Cluster health
```

---

## Completion Checklist

Before declaring the honeypot production-ready:

- [ ] All containers running and healthy
- [ ] Firewall rules applied (outbound blocked)
- [ ] DNAT port redirections working
- [ ] Data flowing to OpenSearch
- [ ] GeoIP enrichment functional
- [ ] Dashboard created and accessible
- [ ] External connectivity tested
- [ ] Log rotation configured
- [ ] Backup strategy in place
- [ ] Monitoring/alerting configured
- [ ] Documentation reviewed

---

**Congratulations!** Your honeypot is now fully operational and collecting threat intelligence.

Monitor for 24-48 hours to start seeing real attack patterns, then use the collected data to inform your security posture and threat awareness.
