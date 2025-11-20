# Honeypot Dashboard Queries

This document contains useful queries and visualizations for analyzing honeypot data in OpenSearch Dashboards.

## Getting Started

1. Open OpenSearch Dashboards at http://localhost:5601
2. Go to **Management** → **Index Patterns** → **Create index pattern**
3. Enter pattern: `honeypot-*`
4. Select timestamp field: `@timestamp`
5. Click **Create index pattern**

## Key Visualizations

### 1. Events Over Time
**Type:** Line Chart
**Query:**
```
Index pattern: honeypot-*
Y-axis: Count
X-axis: Date Histogram on @timestamp (interval: auto)
```

### 2. Top Source IPs
**Type:** Data Table
**Query:**
```json
{
  "size": 0,
  "aggs": {
    "top_ips": {
      "terms": {
        "field": "source.ip",
        "size": 20,
        "order": {
          "_count": "desc"
        }
      }
    }
  }
}
```

**Visualization Config:**
- Metric: Count
- Buckets: Terms aggregation on `source.ip.keyword`
- Size: 20

### 3. Top Usernames Attempted
**Type:** Tag Cloud / Data Table
**Query:**
```json
{
  "size": 0,
  "aggs": {
    "top_usernames": {
      "terms": {
        "field": "user.name",
        "size": 50,
        "order": {
          "_count": "desc"
        }
      }
    }
  }
}
```

### 4. Top Passwords Attempted
**Type:** Data Table
**Query:**
```json
{
  "size": 0,
  "aggs": {
    "top_passwords": {
      "terms": {
        "field": "user.password",
        "size": 50,
        "order": {
          "_count": "desc"
        }
      }
    }
  }
}
```

### 5. Geographic Distribution of Attacks
**Type:** Coordinate Map
**Query:**
```
Geohash aggregation on source.geo.location
```

**Configuration:**
- Metric: Count
- Buckets: Geohash on `source.geo.location`

### 6. Top ASNs (Autonomous Systems)
**Type:** Horizontal Bar
**Query:**
```json
{
  "size": 0,
  "aggs": {
    "top_asns": {
      "terms": {
        "field": "source.as_org",
        "size": 15,
        "order": {
          "_count": "desc"
        }
      }
    }
  }
}
```

### 7. Top Commands Executed (SSH/Telnet)
**Type:** Data Table
**Query:**
```json
{
  "query": {
    "bool": {
      "must": [
        { "exists": { "field": "input" } },
        { "term": { "log_type": "cowrie" } }
      ]
    }
  },
  "aggs": {
    "top_commands": {
      "terms": {
        "field": "input.keyword",
        "size": 30,
        "order": {
          "_count": "desc"
        }
      }
    }
  }
}
```

### 8. HTTP URLs Requested
**Type:** Data Table
**Query:**
```json
{
  "query": {
    "bool": {
      "must": [
        { "exists": { "field": "url" } },
        { "term": { "log_type": "opencanary" } }
      ]
    }
  },
  "aggs": {
    "top_urls": {
      "terms": {
        "field": "url",
        "size": 30,
        "order": {
          "_count": "desc"
        }
      }
    }
  }
}
```

### 9. Attack Protocol Distribution
**Type:** Pie Chart
**Query:**
```json
{
  "size": 0,
  "aggs": {
    "protocols": {
      "terms": {
        "field": "honeypot"
      }
    }
  }
}
```

### 10. Session Duration Analysis
**Type:** Histogram
**Query:**
```json
{
  "query": {
    "exists": {
      "field": "duration"
    }
  },
  "aggs": {
    "duration_histogram": {
      "histogram": {
        "field": "duration",
        "interval": 10
      }
    }
  }
}
```

## Sample Dashboard Layout

Create a dashboard with these panels:

```
┌────────────────────────────────┬────────────────────────────────┐
│   Events Over Time (24h)       │   Geographic Attack Map        │
│   (Line Chart)                 │   (Coordinate Map)             │
├────────────────────────────────┼────────────────────────────────┤
│   Top 10 Source IPs            │   Top 10 Source Countries      │
│   (Data Table)                 │   (Bar Chart)                  │
├────────────────────────────────┼────────────────────────────────┤
│   Top Usernames (25)           │   Top Passwords (25)           │
│   (Tag Cloud)                  │   (Data Table)                 │
├────────────────────────────────┼────────────────────────────────┤
│   Top Commands                 │   Protocol Distribution        │
│   (Data Table)                 │   (Pie Chart)                  │
└────────────────────────────────┴────────────────────────────────┘
```

## Useful Filters

### Show only SSH attacks:
```
log_type: "cowrie" AND protocol: "ssh"
```

### Show only successful logins:
```
eventid: "cowrie.login.success"
```

### Show attacks from specific country:
```
source.geo.country: "China"
```

### Show recent attacks (last 1 hour):
```
@timestamp: [now-1h TO now]
```

## Saved Searches

### Failed Login Attempts
```json
{
  "query": {
    "bool": {
      "should": [
        { "term": { "eventid": "cowrie.login.failed" } },
        { "term": { "eventid": "cowrie.login.success" } }
      ]
    }
  },
  "sort": [
    { "@timestamp": { "order": "desc" } }
  ]
}
```

### Command Execution Events
```json
{
  "query": {
    "term": {
      "eventid": "cowrie.command.input"
    }
  },
  "sort": [
    { "@timestamp": { "order": "desc" } }
  ]
}
```

### File Download Attempts
```json
{
  "query": {
    "term": {
      "eventid": "cowrie.session.file_download"
    }
  },
  "sort": [
    { "@timestamp": { "order": "desc" } }
  ]
}
```

## Weekly TI Summary Query

Run this query to generate a weekly threat intelligence summary:

```json
{
  "query": {
    "range": {
      "@timestamp": {
        "gte": "now-7d",
        "lte": "now"
      }
    }
  },
  "aggs": {
    "total_events": {
      "value_count": {
        "field": "@timestamp"
      }
    },
    "unique_ips": {
      "cardinality": {
        "field": "source.ip"
      }
    },
    "top_countries": {
      "terms": {
        "field": "source.geo.country",
        "size": 10
      }
    },
    "top_asns": {
      "terms": {
        "field": "source.as_org",
        "size": 10
      }
    },
    "top_usernames": {
      "terms": {
        "field": "user.name",
        "size": 20
      }
    },
    "top_passwords": {
      "terms": {
        "field": "user.password",
        "size": 20
      }
    },
    "top_commands": {
      "terms": {
        "field": "input.keyword",
        "size": 20
      }
    }
  }
}
```

## Export Dashboard

To export your dashboard configuration:
1. Go to **Management** → **Saved Objects**
2. Select your dashboards, visualizations, and searches
3. Click **Export**
4. Save the exported JSON file for backup or sharing
