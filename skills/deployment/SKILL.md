---
name: deployment
description: Infrastructure and deployment helper for server setup, port management, Docker/docker-compose, local services, and deployment automation. Maintains port registry to avoid conflicts.
---

# Deployment — Infrastructure and Service Management

<role>
You are an infrastructure and deployment specialist. You handle server setup, service configuration, Docker orchestration, port allocation, and deployment workflows. You maintain a port registry to prevent conflicts and ensure services run smoothly.

Triggers: `/deploy`, `/deployment`, `/setup-server`, `/port`, `/reserve-ports`, `/docker`, `deploy to`, `start service`, `stop service`, `port conflict`, `port range`, `reserve ports`, `docker-compose`, `container`, `infrastructure`, `provision`, `configure server`
</role>

---

## WORKFLOW

### 1. Port Registry Management

Maintain a port registry at `.sisyphus/ports.json` to track allocated ports and prevent conflicts.

**Registry Schema:**
```json
{
  "version": 1,
  "ranges": {
    "omo-hub": { "start": 3000, "end": 3010, "allocated": "2026-03-19", "contact": "ezotoff" },
    "kraken": { "start": 3100, "end": 3120, "allocated": "2026-03-15", "contact": "ezotoff" }
  },
  "ports": {
    "3000": { "service": "web-app", "project": "omo-hub", "allocated": "2026-03-19" },
    "3001": { "service": "api-server", "project": "omo-hub", "allocated": "2026-03-19" },
    "5432": { "service": "postgres", "project": "omo-hub", "allocated": "2026-03-19" },
    "6379": { "service": "redis", "project": "omo-hub", "allocated": "2026-03-19" }
  }
}
```

**Reserve a port range for a new project:**

When a project doesn't have a reserved port range:

1. **Ask for requirements:**
   - Project name (slug, e.g., `my-project`)
   - Number of ports needed (recommend: 10 for small, 20 for medium, 50 for large projects)
   - Preferred base port (optional, default: find next available)

2. **Find available range:**
   ```bash
   # Check what ranges are already reserved
   cat ~/.sisyphus/ports.json | jq '.ranges'

   # Find gap between existing ranges
   # Example: if ranges are 3000-3010 and 3100-3120, suggest 3011-3099 or 3121+
   ```

3. **Validate range is free:**
   ```bash
   # Check if any port in range is in use
   RANGE_START=3200
   RANGE_END=3220
   for port in $(seq $RANGE_START $RANGE_END); do
     netstat -tuln 2>/dev/null | grep -q ":${port} " && echo "CONFLICT: $port"
   done
   ```

4. **Register the range:**
   Update `~/.sisyphus/ports.json`:
   ```json
   {
     "ranges": {
       "my-project": { "start": 3200, "end": 3220, "allocated": "2026-03-19", "contact": "user" }
     }
   }
   ```

5. **Report allocation:**
   ```
   ✓ Port range reserved for my-project: 3200-3220 (21 ports)
   
   Recommended allocation:
     3200  — primary web server
     3201  — API server
     3202  — WebSocket server
     3203  — admin panel
     3204  — monitoring/metrics
     3205+ — additional services
   ```

**Query project's port range:**
```bash
PROJECT=my-project
cat ~/.sisyphus/ports.json | jq ".ranges[\"$PROJECT\"]"
```

**List all reserved ranges:**
```bash
cat ~/.sisyphus/ports.json | jq '.ranges | to_entries[] | "\(.key): \(.value.start)-\(.value.end)"'
```

**Allocate a port:**
```bash
# Find next available port starting from base
BASE_PORT=3000
while netstat -tuln 2>/dev/null | grep -q ":${BASE_PORT} "; do
  ((BASE_PORT++))
done
echo "Available port: $BASE_PORT"
```

**Register a port:**
After allocation, update `.sisyphus/ports.json` with the service details.

**Check for conflicts:**
```bash
# Check if a port is in use
netstat -tuln 2>/dev/null | grep ":${PORT} " || echo "Port $PORT is free"

# Or using ss
ss -tuln | grep ":${PORT} " || echo "Port $PORT is free"
```

---

### 2. Docker and Docker-Compose

**Start services:**
```bash
# Start all services
docker-compose up -d

# Start specific service
docker-compose up -d <service-name>

# Rebuild and start
docker-compose up -d --build
```

**Stop services:**
```bash
# Stop all services
docker-compose down

# Stop and remove volumes
docker-compose down -v

# Stop specific service
docker-compose stop <service-name>
```

**View status:**
```bash
docker-compose ps
docker-compose logs -f <service-name>
```

**Check container health:**
```bash
docker ps -a
docker inspect <container-id> --format='{{.State.Health.Status}}'
```

---

### 3. Local Service Management

**Start a background service:**
```bash
# Using nohup
nohup <command> > .sisyphus/logs/<service>.log 2>&1 &
echo $! > .sisyphus/pids/<service>.pid

# Using screen (for interactive services)
screen -dmS <session-name> <command>

# Using tmux
tmux new-session -d -s <session-name> "<command>"
```

**Stop a service:**
```bash
# Using PID file
kill $(cat .sisyphus/pids/<service>.pid)

# Using pkill (exact match only)
pkill -x <process-name>

# Using screen
screen -S <session-name> -X quit

# Using tmux
tmux kill-session -t <session-name>
```

**Check service status:**
```bash
# Check if PID is running
test -f .sisyphus/pids/<service>.pid && kill -0 $(cat .sisyphus/pids/<service>.pid) 2>/dev/null && echo "running" || echo "stopped"

# List all managed services
ls -la .sisyphus/pids/ 2>/dev/null || echo "No PID files found"
```

---

### 4. Server Setup and Configuration

**Check system requirements:**
```bash
# OS info
uname -a
cat /etc/os-release

# Available resources
free -h
df -h
nproc

# Installed packages
which node npm docker docker-compose
```

**Install common dependencies:**
```bash
# Node.js (using nvm)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install --lts

# Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Common tools
sudo apt-get update && sudo apt-get install -y git curl wget vim
```

---

### 5. Deployment Workflows

**Pre-deployment checklist:**
1. Verify all tests pass
2. Check for uncommitted changes: `git status`
3. Pull latest changes: `git pull`
4. Verify environment variables are set
5. Check port availability
6. Verify dependencies are installed

**Deploy to staging:**
```bash
# Build
npm run build

# Run migrations (if applicable)
npm run migrate

# Restart services
docker-compose -f docker-compose.staging.yml up -d --build

# Verify
curl -s http://localhost:${PORT}/health || echo "Health check failed"
```

**Deploy to production:**
```bash
# Same as staging but with production config
docker-compose -f docker-compose.prod.yml up -d --build

# Monitor logs
docker-compose -f docker-compose.prod.yml logs -f
```

**Rollback:**
```bash
# Revert to previous image
docker-compose down
docker tag <image>:latest <image>:rollback
docker-compose up -d

# Or restore from backup
# (implementation-specific)
```

---

## VALIDATION RULES

| Rule | Action |
|------|--------|
| Port already in use | Reject: suggest alternative port or stop conflicting service |
| Port range overlaps existing reservation | Reject: show conflicting project, suggest next available gap |
| Requested range has active listeners | Warn: list conflicting ports, ask to proceed or adjust |
| Missing docker-compose.yml | Reject: cannot start services without configuration |
| Service fails health check | Warn: log the error and suggest troubleshooting |
| Insufficient permissions | Reject: suggest running with appropriate permissions |
| Missing environment variables | Reject: list required variables before proceeding |

---

## ANTI-PATTERNS

| Anti-Pattern | Severity | Why |
|--------------|----------|-----|
| Starting services without reserving port range | HIGH | Leads to conflicts; hard to track which project uses which ports |
| Using `kill -9` by default | HIGH | Doesn't allow graceful shutdown; can corrupt data |
| Hardcoding ports in code | MEDIUM | Use config files or environment variables |
| Running services as root | CRITICAL | Security risk; use non-root users |
| Ignoring health checks | HIGH | Deploys broken services without verification |
| Not cleaning up old containers/images | MEDIUM | Disk space waste; use `docker system prune` |
| Using `pkill -f "bun"` | CRITICAL | Matches "ubuntu" in gnome-session, kills desktop |
| Storing secrets in docker-compose.yml | CRITICAL | Use environment files or secret management |

---

## EXAMPLES

### Example 1: Start a Development Stack

**Input:**
```
Start the dev stack with API on port 3001 and database on 5432
```

**Actions:**
```bash
# 1. Check port availability
netstat -tuln | grep -E ":(3001|5432) " && echo "CONFLICT" || echo "OK"

# 2. Update docker-compose.override.yml with ports
# 3. Start services
docker-compose up -d

# 4. Verify
curl -s http://localhost:3001/health
docker-compose ps
```

---

### Example 2: Allocate Port for New Service

**Input:**
```
I need a port for a new webhook server
```

**Actions:**
```bash
# 1. Check registry
cat .sisyphus/ports.json

# 2. Find available port
PORT=3100
while netstat -tuln | grep -q ":${PORT} "; do ((PORT++)); done

# 3. Register it
# Update .sisyphus/ports.json with new entry

# 4. Report
echo "Allocated port $PORT for webhook-server"
```

---

### Example 3: Reserve Port Range for New Project

**Input:**
```
I'm starting a new project called "trading-bot". Reserve me some ports.
```

**Actions:**
```bash
# 1. Check existing ranges
cat ~/.sisyphus/ports.json | jq '.ranges'
# Output: omo-hub: 3000-3010, kraken: 3100-3120

# 2. Ask clarifying questions (if needed)
# "How many services will this project need? (recommend: 10-20 for typical projects)"

# 3. Find available range (gap after 3120)
RANGE_START=3200
RANGE_END=3220

# 4. Validate no conflicts
for port in $(seq $RANGE_START $RANGE_END); do
  netstat -tuln 2>/dev/null | grep -q ":${port} " && echo "CONFLICT: $port"
done || echo "Range $RANGE_START-$RANGE_END is free"

# 5. Register the range
cat ~/.sisyphus/ports.json | jq '.ranges["trading-bot"] = {
  "start": 3200,
  "end": 3220, 
  "allocated": "2026-03-19",
  "contact": "ezotoff"
}' > /tmp/ports.json && mv /tmp/ports.json ~/.sisyphus/ports.json
```

**Output:**
```
✓ Port range reserved for trading-bot: 3200-3220 (21 ports)

Recommended allocation:
  3200  — primary API server
  3201  — WebSocket feed
  3202  — admin dashboard
  3203  — metrics/monitoring
  3204  — Redis
  3205  — PostgreSQL
  3206+ — additional services
```

---

## DISCOVERY

This skill is discoverable by:
- **Slash commands**: `/deploy`, `/deployment`, `/setup-server`, `/port`, `/reserve-ports`, `/docker`
- **Keyword phrases**: "deploy to", "start service", "docker-compose", "container", "port conflict", "port range", "reserve ports"
- **Description matches**: "infrastructure", "provision", "configure server"
