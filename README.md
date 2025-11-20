# Multi-Protocol Honeypot System

A production-ready honeypot deployment combining **Cowrie** (SSH/Telnet emulation) and **OpenCanary** (HTTP service) with centralized logging, GeoIP enrichment, and threat intelligence analysis capabilities.

## 🎯 Overview

This honeypot system captures and analyzes malicious traffic targeting SSH, Telnet, and HTTP services. All activity is logged, enriched with geographic and ASN data, and visualized through OpenSearch Dashboards for threat intelligence analysis.

### Key Features

- **Multi-Protocol Coverage**: SSH, Telnet (Cowrie) + HTTP (OpenCanary)
- **Secure by Default**: Outbound traffic blocked; only DNS, NTP, and system updates allowed
- **Centralized Logging**: All events aggregated in OpenSearch
- **GeoIP Enrichment**: Automatic geographic and ASN data enrichment
- **Real-time Analysis**: Pre-configured dashboards for threat intelligence
- **Attack Capture**: Logs IP addresses, credentials, commands, and URLs
- **Easy Deployment**: Single command deployment with Docker Compose

## 📋 Success Criteria

✅ **Inbound Hits Recorded**: IP addresses, credentials, and command attempts logged
✅ **Top IPs/ASNs Visible**: Dashboard showing attack sources
✅ **Credential Patterns**: Most common username/password combinations tracked
✅ **Outbound Blocked**: Default DROP policy with whitelist for essential services
✅ **Weekly TI Summary**: Query templates for generating threat intelligence reports

## 🔧 Prerequisites

- Linux VM (Ubuntu 20.04+ or Debian 11+ recommended)
- Docker and Docker Compose installed
- Root access (for firewall configuration)
- Minimum 2GB RAM, 20GB disk space
- Public IP address or port forwarding configured

### Installation

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose
sudo apt-get update
sudo apt-get install -y docker-compose

# Clone this repository
git clone <repository-url>
cd honeypot
```

## 🚀 Quick Start

### 1. Deploy the Honeypot

```bash
# Run deployment script (with root for firewall setup)
sudo bash scripts/deploy.sh
```

The deployment script will:
1. Check prerequisites
2. Stop existing containers
3. Create necessary directories
4. Configure firewall rules (optional)
5. Start all services
6. Configure OpenSearch
7. Run validation tests

### 2. Configure Firewall (Manual)

If you skipped automatic firewall setup, run:

```bash
sudo bash scripts/firewall-setup.sh
```

This configures:
- **DNAT rules**: 22→2222 (SSH), 23→2323 (Telnet), 80→8080 (HTTP)
- **Outbound blocking**: DROP by default
- **Whitelist**: DNS (53), NTP (123), HTTP/HTTPS (80, 443)

### 3. Verify Deployment

```bash
bash scripts/validate.sh
```

### 4. Access Dashboards

Open OpenSearch Dashboards: `http://localhost:5601`

**First Time Setup:**
1. Navigate to **Management** → **Index Patterns**
2. Create pattern: `honeypot-*`
3. Select timestamp field: `@timestamp`
4. Click **Create**

## 📊 Building Dashboards

Use the queries in `opensearch/dashboards/dashboard-queries.md` to create visualizations:

### Key Visualizations

1. **Events Over Time**: Line chart showing attack trends
2. **Top Source IPs**: Data table of most active attackers
3. **Geographic Map**: Coordinate map showing attack origins
4. **Top Usernames**: Tag cloud of attempted usernames
5. **Top Passwords**: Table of most common passwords
6. **Command Analysis**: Most executed commands in SSH sessions
7. **Protocol Distribution**: Pie chart showing attack types

### Sample Dashboard Queries

```json
# Top 20 Source IPs
{
  "size": 0,
  "aggs": {
    "top_ips": {
      "terms": {
        "field": "source.ip",
        "size": 20
      }
    }
  }
}

# Weekly Summary
{
  "query": {
    "range": {
      "@timestamp": {
        "gte": "now-7d"
      }
    }
  },
  "aggs": {
    "unique_ips": {"cardinality": {"field": "source.ip"}},
    "top_countries": {"terms": {"field": "source.geo.country", "size": 10}},
    "top_usernames": {"terms": {"field": "user.name", "size": 20}}
  }
}
```

## 🗂️ Project Structure

```
honeypot/
├── docker-compose.yml           # Main orchestration file
├── README.md                    # This file
│
├── cowrie/
│   ├── cowrie.cfg              # Cowrie configuration
│   ├── data/                   # Cowrie data directory
│   └── logs/                   # Cowrie log files
│
├── opencanary/
│   └── opencanary.conf         # OpenCanary configuration
│
├── filebeat/
│   └── filebeat.yml            # Log shipper configuration
│
├── opensearch/
│   ├── index-templates/        # Index templates and pipelines
│   │   ├── honeypot-template.json
│   │   └── geoip-pipeline.json
│   └── dashboards/
│       └── dashboard-queries.md # Dashboard query examples
│
├── scripts/
│   ├── deploy.sh               # Main deployment script
│   ├── validate.sh             # Validation and testing
│   ├── firewall-setup.sh       # Firewall configuration
│   └── setup-opensearch.sh     # OpenSearch setup
│
└── logs/
    └── opencanary/             # OpenCanary logs
```

## 🔒 Security Architecture

### Network Security

```
Internet
   ↓
[Firewall]
   ↓
Port Redirection (DNAT):
   22  → 2222  (SSH → Cowrie)
   23  → 2323  (Telnet → Cowrie)
   80  → 8080  (HTTP → OpenCanary)
   ↓
[Honeypot Services]
   ↓
[Filebeat] → [OpenSearch]
```

### Firewall Rules

**INPUT**: Accept honeypot ports, management SSH, dashboards
**OUTPUT**: DROP by default, whitelist DNS/NTP/updates
**FORWARD**: DROP all

### Container Security

- `cap_drop: ALL` - Drop all capabilities
- `cap_add: NET_BIND_SERVICE` - Only allow port binding
- `security_opt: no-new-privileges` - Prevent privilege escalation
- Isolated Docker network

## 📈 Monitoring & Analysis

### Real-time Log Monitoring

```bash
# View Cowrie logs
docker logs -f honeypot-cowrie

# View OpenCanary logs
docker logs -f honeypot-opencanary

# View Filebeat logs
docker logs -f honeypot-filebeat

# View raw JSON logs
tail -f cowrie/logs/cowrie.json
tail -f logs/opencanary/opencanary.json
```

### OpenSearch Queries

Access OpenSearch API directly:

```bash
# Cluster health
curl http://localhost:9200/_cluster/health?pretty

# Recent events
curl http://localhost:9200/honeypot-*/_search?size=10&pretty

# Count by source IP
curl -X GET "http://localhost:9200/honeypot-*/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "aggs": {
    "ips": {"terms": {"field": "source.ip", "size": 20}}
  }
}'
```

## 🧪 Testing

### Internal Testing

```bash
# Test SSH (will be logged)
ssh -p 2222 root@localhost
# Try: root/root, admin/admin, test/test

# Test Telnet
telnet localhost 2323

# Test HTTP
curl http://localhost:8080
```

### External Testing

```bash
# From another machine
nmap -p 22,23,80 <honeypot-ip>
ssh user@<honeypot-ip>
```

### Validation Script

```bash
bash scripts/validate.sh
```

Tests:
- OpenSearch availability
- Container status
- Port connectivity
- Log file creation
- Index template configuration
- Data ingestion

## 📊 Weekly Threat Intelligence Summary

Generate weekly reports:

1. Open OpenSearch Dashboards
2. Go to **Dev Tools**
3. Run the weekly summary query (see `opensearch/dashboards/dashboard-queries.md`)
4. Export results to JSON/CSV

**Key Metrics:**
- Total attack events
- Unique source IPs
- Top 10 countries
- Top 10 ASNs
- Most common credentials
- Most executed commands
- Download URLs attempted

## 🔧 Configuration

### Cowrie Configuration

Edit `cowrie/cowrie.cfg`:

```ini
[honeypot]
hostname = srv-prod-01        # Hostname shown to attackers
interactive_timeout = 180     # Session timeout

[ssh]
version = SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.1  # SSH banner
```

### OpenCanary Configuration

Edit `opencanary/opencanary.conf`:

```json
{
  "http.enabled": true,
  "http.port": 8080,
  "http.banner": "Apache/2.4.49",
  "http.skin": "nasLogin"
}
```

### Filebeat Configuration

Edit `filebeat/filebeat.yml` to modify:
- Log paths
- Index naming
- Enrichment processors
- Output destinations

## 🚨 Troubleshooting

### Containers Not Starting

```bash
# Check container logs
docker-compose logs

# Check disk space
df -h

# Check permissions
ls -la cowrie/logs logs/opencanary
```

### No Data in OpenSearch

```bash
# Check Filebeat status
docker logs honeypot-filebeat

# Verify log files exist
ls -la cowrie/logs/
ls -la logs/opencanary/

# Check OpenSearch indices
curl http://localhost:9200/_cat/indices?v
```

### Firewall Issues

```bash
# List iptables rules
sudo iptables -L -n -v

# List nftables rules
sudo nft list ruleset

# Check NAT rules
sudo iptables -t nat -L -n -v
```

### Port Already in Use

```bash
# Find process using port
sudo lsof -i :2222
sudo lsof -i :9200

# Stop conflicting services
sudo systemctl stop ssh  # If real SSH on 22 conflicts
```

## 🔄 Maintenance

### Backup Data

```bash
# Backup logs
tar -czf honeypot-logs-$(date +%Y%m%d).tar.gz cowrie/logs logs/opencanary

# Export OpenSearch data
curl -X GET "http://localhost:9200/honeypot-*/_search?scroll=1m" -H 'Content-Type: application/json' -d'
{
  "size": 10000,
  "query": {"match_all": {}}
}' > opensearch-export.json
```

### Rotate Logs

```bash
# Clean old Cowrie logs
find cowrie/logs -name "*.log.*" -mtime +30 -delete

# Clean old OpenSearch indices
curl -X DELETE "http://localhost:9200/honeypot-$(date -d '30 days ago' +%Y.%m.%d)"
```

### Update Containers

```bash
docker-compose pull
docker-compose up -d
```

## 🎓 Learning Resources

- **Cowrie Documentation**: https://cowrie.readthedocs.io/
- **OpenCanary Documentation**: https://github.com/thinkst/opencanary
- **OpenSearch Documentation**: https://opensearch.org/docs/
- **Filebeat Documentation**: https://www.elastic.co/guide/en/beats/filebeat/

## ⚠️ Important Warnings

1. **Never expose OpenSearch Dashboards publicly** - Use SSH tunnel or VPN
2. **Monitor outbound traffic** - Ensure malware can't phone home
3. **Regular updates** - Keep Docker images updated for security
4. **Legal compliance** - Ensure honeypot deployment complies with local laws
5. **Network isolation** - Deploy in isolated VLAN/network segment if possible
6. **Backup regularly** - Threat intelligence data is valuable

## 🚀 Next Steps (Post-MVP)

- **Banner Customization**: Tune SSH/Telnet banners to mimic specific targets
- **Fake Filesystem**: Customize Cowrie filesystem to appear more realistic
- **Rate Limiting**: Implement per-IP rate limits to prevent DoS
- **Additional Protocols**: Add FTP, MySQL, RDP services via OpenCanary
- **Weekly PDF Reports**: Automate threat intelligence report generation
- **SIEM Integration**: Forward logs to external SIEM (Splunk, ELK, etc.)
- **Threat Feed Integration**: Compare IPs against known threat feeds
- **Automated Response**: Block repeat offenders automatically

## 📝 License

This project is provided as-is for educational and defensive security purposes.

## 🤝 Contributing

Contributions welcome! Please ensure:
- Code follows security best practices
- Documentation is updated
- Scripts are tested

## 📧 Support

For issues, questions, or contributions, please open an issue in the repository.

---

**Remember**: This is a honeypot. It will attract malicious traffic. Ensure proper security measures are in place!
