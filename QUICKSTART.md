# Quick Start Guide

Get your honeypot up and running in 5 minutes!

## Prerequisites

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y docker.io docker-compose git

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker
```

## Installation

```bash
# Clone repository
git clone <repository-url>
cd honeypot

# Deploy (requires root for firewall)
sudo bash scripts/deploy.sh
```

## What Gets Deployed?

- **Cowrie** - SSH/Telnet honeypot on ports 2222/2323
- **OpenCanary** - HTTP honeypot on port 8080
- **OpenSearch** - Log storage and search engine
- **Filebeat** - Log shipper with GeoIP enrichment
- **Dashboards** - Visualization interface

## Access

| Service | URL | Purpose |
|---------|-----|---------|
| OpenSearch Dashboards | http://localhost:5601 | View attack data |
| OpenSearch API | http://localhost:9200 | Query logs directly |
| Cowrie SSH | localhost:2222 | SSH honeypot |
| Cowrie Telnet | localhost:2323 | Telnet honeypot |
| OpenCanary HTTP | http://localhost:8080 | HTTP honeypot |

## Setup Dashboard

1. Open http://localhost:5601
2. Go to **Management** → **Index Patterns** → **Create**
3. Pattern: `honeypot-*`
4. Timestamp: `@timestamp`
5. Click **Create**

## Test It

```bash
# Test SSH (password: anything)
ssh root@localhost -p 2222

# Test HTTP
curl http://localhost:8080

# Monitor activity
bash scripts/monitor.sh
```

## View Logs

```bash
# Real-time container logs
docker logs -f honeypot-cowrie
docker logs -f honeypot-opencanary

# JSON logs
tail -f cowrie/logs/cowrie.json
tail -f logs/opencanary/opencanary.json
```

## Monitor Stats

```bash
# Run monitoring dashboard
bash scripts/monitor.sh
```

Shows:
- Total events
- Top IPs and countries
- Most common credentials
- Protocol distribution
- Container status

## Port Forwarding (Optional)

To expose to internet:

```bash
# Option 1: Using firewall script (includes DNAT)
sudo bash scripts/firewall-setup.sh

# Option 2: Manual iptables NAT
sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222
sudo iptables -t nat -A PREROUTING -p tcp --dport 23 -j REDIRECT --to-port 2323
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
```

## Security Checklist

- [ ] Firewall rules configured (outbound blocked)
- [ ] OpenSearch Dashboards NOT exposed publicly
- [ ] Regular log backups configured
- [ ] Monitoring script scheduled (cron)
- [ ] System updates enabled

## Troubleshooting

**No containers running?**
```bash
docker-compose ps
docker-compose logs
```

**Can't connect to services?**
```bash
sudo netstat -tlnp | grep -E '2222|2323|8080|5601|9200'
```

**No data in OpenSearch?**
```bash
# Check Filebeat
docker logs honeypot-filebeat

# Check indices
curl http://localhost:9200/_cat/indices?v
```

**Firewall blocking legitimate access?**
```bash
# Check rules
sudo iptables -L -n -v
sudo nft list ruleset
```

## Maintenance

```bash
# View stats
bash scripts/monitor.sh

# Clean old logs (30+ days)
bash scripts/cleanup.sh

# Backup logs
tar -czf backup-$(date +%Y%m%d).tar.gz cowrie/logs logs/opencanary

# Update containers
docker-compose pull
docker-compose up -d
```

## Next Steps

1. **Create Dashboards** - See `opensearch/dashboards/dashboard-queries.md`
2. **Customize Banners** - Edit `cowrie/cowrie.cfg`
3. **Add More Services** - Edit `opencanary/opencanary.conf`
4. **Schedule Reports** - Set up cron jobs for weekly reports
5. **External Testing** - Use nmap from external host

## Production Deployment

```bash
# Use production config
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Set up SSL for dashboards (recommended)
# Use nginx reverse proxy with Let's Encrypt
```

## Common Commands

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# Restart service
docker-compose restart cowrie

# View logs
docker-compose logs -f

# Check status
bash scripts/validate.sh

# Monitor activity
bash scripts/monitor.sh

# Clean old data
bash scripts/cleanup.sh
```

## Getting Help

- Full documentation: See `README.md`
- Dashboard queries: See `opensearch/dashboards/dashboard-queries.md`
- Configuration files: See individual service directories

## What to Expect

**First 24 hours:**
- Random port scans
- Some SSH/Telnet login attempts
- Basic credential testing

**After 1 week:**
- Consistent attack patterns
- Multiple IPs from similar ASNs
- Common credential combinations visible

**After 1 month:**
- Comprehensive threat intelligence
- Geographic attack trends
- Malware download attempts
- Botnet activity patterns

---

**Remember:** This is a honeypot. It WILL attract malicious traffic. Ensure proper isolation!
