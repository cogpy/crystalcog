# CrystalCog Production Deployment Guide

The supported production path is the repository's `Dockerfile.production` and
`docker-compose.production.yml`. It runs the Crystal Pygmalion platform rather
than the removed CMake/Python monorepo configuration.

## Required configuration

Generate independent 32-byte-or-longer signing secrets and point CrystalCog at an
OpenAI-compatible inference server:

```bash
export SECRET_KEY_BASE="$(openssl rand -hex 32)"
export JWT_SECRET="$(openssl rand -hex 32)"
export APHRODITE_URL="http://inference.example:8000"
docker compose -f docker-compose.production.yml up --build -d
```

The container fails closed when required production secrets are absent. Paphos
data is stored in the `crystalcog-data` volume. Keep the Galatea port behind TLS
and do not expose the Paphos port directly unless another trusted service needs
it.

CogServer is separately deployable. When binding outside loopback it requires
`COGSERVER_AUTH_TOKEN`; clients use a bearer token for HTTP/WebSocket and the
`auth <token>` command for Telnet. Request body and rate limits are configured
with the `COGSERVER_*`, `PAPHOS_*`, and `GALATEA_*` environment variables
documented by the server constructors.

Before deployment, run:

```bash
./scripts/verify.sh all
```

This guide provides comprehensive instructions for deploying CrystalCog to production environments.

## Overview

The production deployment tools include:

- **Multi-stage Docker production builds** with security optimizations
- **Docker Compose** stack with monitoring, logging, and database services
- **Kubernetes** deployment manifests for container orchestration
- **Automated deployment scripts** with backup and rollback capabilities
- **CI/CD pipelines** for continuous deployment
- **Monitoring and logging** with Prometheus, Grafana, and ELK stack
- **Security configurations** including SSL, firewall, and fail2ban

## Quick Start

### 1. Production Server Setup

Run the automated setup script on your production server:

```bash
# Download and run the setup script
curl -sSL https://raw.githubusercontent.com/EchoCog/crystalcog/main/scripts/production/setup-production.sh | sudo bash

# Or clone the repository and run locally
git clone https://github.com/EchoCog/crystalcog.git
cd crystalcog
sudo ./scripts/production/setup-production.sh
```

### 2. Configure Environment

Edit the production environment file:

```bash
cd /opt/crystalcog
sudo -u crystalcog cp .env.production.template .env.production
sudo -u crystalcog nano .env.production
```

### 3. Deploy

Deploy using the automated deployment script:

```bash
cd /opt/crystalcog
sudo -u crystalcog ./scripts/production/deploy.sh
```

## Architecture

### Production Stack Components

| Service | Purpose | Ports | Resources |
|---------|---------|-------|-----------|
| CrystalCog App | Main application server | 5000, 17001, 18001, 8080 | 2 CPU, 2GB RAM |
| PostgreSQL | Primary database | 5432 | 1 CPU, 1GB RAM |
| Redis | Caching and session store | 6379 | 0.5 CPU, 512MB RAM |
| Nginx | Reverse proxy and load balancer | 80, 443 | 0.5 CPU, 256MB RAM |
| Prometheus | Metrics collection | 9090 | 0.5 CPU, 512MB RAM |
| Grafana | Monitoring dashboards | 3000 | 0.3 CPU, 256MB RAM |
| Elasticsearch | Log aggregation | 9200 | 1 CPU, 1GB RAM |
| Logstash | Log processing | - | 0.5 CPU, 512MB RAM |
| Kibana | Log visualization | 5601 | 0.5 CPU, 512MB RAM |

### Network Architecture

```
Internet → Nginx (SSL Termination) → CrystalCog App
                                   ↓
                              PostgreSQL + Redis
                                   ↓
                          Monitoring Stack (Prometheus/Grafana)
                                   ↓
                           Logging Stack (ELK)
```

## Deployment Methods

### Docker Compose Deployment

**Best for:** Single-server deployments, development staging

```bash
# Production deployment
docker-compose -f docker-compose.production.yml --env-file .env.production up -d

# Check status
docker-compose -f docker-compose.production.yml ps

# View logs
docker-compose -f docker-compose.production.yml logs -f crystalcog-app
```

### Kubernetes Deployment

**Best for:** Multi-server clusters, high availability

```bash
# Apply Kubernetes manifests
kubectl apply -f deployments/k8s/production/

# Check deployment status
kubectl get pods -n crystalcog-production

# View service status
kubectl get services -n crystalcog-production
```

### CI/CD Pipeline Deployment

**Best for:** Automated deployments, GitOps workflows

The GitHub Actions workflow automatically:
1. Builds and tests the application
2. Runs security scans
3. Deploys to staging/production
4. Performs health checks
5. Sends notifications

## Configuration Management

### Environment Variables

Key production environment variables:

```bash
# Database
DATABASE_URL=postgresql://user:pass@postgres:5432/crystalcog_prod
POSTGRES_PASSWORD=<strong-password>

# Application
CRYSTAL_ENV=production
LOG_LEVEL=info
API_PORT=5000
COGSERVER_PORT=17001

# Security
SSL_CERT_PATH=/etc/ssl/certs/crystalcog.crt
SSL_KEY_PATH=/etc/ssl/certs/crystalcog.key

# Monitoring
MONITORING_ENABLED=true
GRAFANA_ADMIN_PASSWORD=<strong-password>

# Backup
BACKUP_ENABLED=true
BACKUP_SCHEDULE="0 2 * * *"
BACKUP_RETENTION_DAYS=30
```

### SSL Certificates

#### Using Let's Encrypt

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificates
sudo certbot certonly --standalone -d crystalcog.example.com

# Copy certificates to application
sudo cp /etc/letsencrypt/live/crystalcog.example.com/fullchain.pem /opt/crystalcog/config/production/ssl/crystalcog.crt
sudo cp /etc/letsencrypt/live/crystalcog.example.com/privkey.pem /opt/crystalcog/config/production/ssl/crystalcog.key
```

#### Using Custom Certificates

```bash
# Place your certificates
sudo cp your-certificate.crt /opt/crystalcog/config/production/ssl/crystalcog.crt
sudo cp your-private-key.key /opt/crystalcog/config/production/ssl/crystalcog.key

# Set proper permissions
sudo chown crystalcog:crystalcog /opt/crystalcog/config/production/ssl/*
sudo chmod 600 /opt/crystalcog/config/production/ssl/crystalcog.key
```

## Monitoring and Observability

### Prometheus Metrics

Access Prometheus at: `https://monitoring.crystalcog.example.com/prometheus/`

Key metrics monitored:
- Application response times
- Database performance
- System resource usage
- Error rates and success rates
- Custom CogServer metrics

### Grafana Dashboards

Access Grafana at: `https://monitoring.crystalcog.example.com/grafana/`

Pre-configured dashboards:
- Application Overview
- Database Performance  
- System Resources
- Error Analysis
- CogServer Analytics

### Logging with ELK Stack

Access Kibana at: `https://monitoring.crystalcog.example.com/kibana/`

Log sources:
- Application logs
- Nginx access/error logs
- System logs
- Container logs

## Backup and Recovery

### Automated Backups

Backups run automatically daily at 2 AM and include:
- PostgreSQL database dump
- Application data volumes
- Configuration files
- SSL certificates

```bash
# Manual backup
/opt/crystalcog/scripts/production/backup.sh

# List backups
ls -la /backup/crystalcog/

# Restore from backup
/opt/crystalcog/scripts/production/deploy.sh --action rollback
```

### Database Backup/Restore

```bash
# Manual database backup
docker-compose -f docker-compose.production.yml exec postgres \
    pg_dump -U crystalcog_user crystalcog_prod > backup.sql

# Restore database
cat backup.sql | docker-compose -f docker-compose.production.yml exec -T postgres \
    psql -U crystalcog_user -d crystalcog_prod
```

## Security Configuration

### Firewall Rules

The setup script configures UFW with these rules:
- SSH (port 22): Allowed
- HTTP (port 80): Allowed 
- HTTPS (port 443): Allowed
- Application ports: Restricted to necessary access
- Monitoring ports: Internal network only

### Fail2ban Protection

Automated IP banning for:
- SSH brute force attacks
- HTTP authentication failures
- Nginx rate limit violations

### Security Headers

Nginx configured with security headers:
- X-Frame-Options
- X-Content-Type-Options
- X-XSS-Protection
- Content Security Policy
- Referrer Policy

## Performance Tuning

### Database Optimization

PostgreSQL configuration in `config/production/postgres/postgresql.conf`:

```conf
# Memory settings
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB

# Connection settings
max_connections = 100
shared_preload_libraries = 'pg_stat_statements'

# Logging
log_min_duration_statement = 1000
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
```

### Application Tuning

Crystal application optimizations:
- Release builds with optimizations
- Static linking for reduced dependencies
- Multi-process architecture via supervisor
- Connection pooling for database access

### Resource Limits

Docker Compose resource limits prevent resource exhaustion:

```yaml
deploy:
  resources:
    limits:
      memory: 2G
      cpus: '2'
    reservations:
      memory: 512M
      cpus: '0.5'
```

## Troubleshooting

### Health Checks

Run comprehensive health checks:

```bash
# Application health check
/opt/crystalcog/scripts/production/healthcheck.sh

# Docker Compose services status
docker-compose -f docker-compose.production.yml ps

# Kubernetes deployment status
kubectl get pods -n crystalcog-production
```

### Log Analysis

```bash
# Application logs
docker-compose -f docker-compose.production.yml logs crystalcog-app

# Database logs
docker-compose -f docker-compose.production.yml logs postgres

# Nginx logs
docker-compose -f docker-compose.production.yml logs nginx

# System logs
sudo journalctl -u crystalcog.service -f
```

### Common Issues

#### Service Won't Start

1. Check Docker daemon: `sudo systemctl status docker`
2. Verify environment file: `cat /opt/crystalcog/.env.production`
3. Check port conflicts: `sudo netstat -tlnp`
4. Review logs: `docker-compose logs`

#### Database Connection Issues

1. Verify PostgreSQL status: `docker-compose ps postgres`
2. Check database credentials in environment file
3. Test connection: `docker-compose exec postgres psql -U crystalcog_user -d crystalcog_prod`

#### SSL Certificate Problems

1. Verify certificate files exist and have correct permissions
2. Check certificate validity: `openssl x509 -in cert.crt -text -noout`
3. Restart Nginx: `docker-compose restart nginx`

#### Performance Issues

1. Check resource usage: `htop`, `docker stats`
2. Review Grafana dashboards for bottlenecks
3. Analyze slow query logs in PostgreSQL
4. Check disk space: `df -h`

## Scaling and High Availability

### Horizontal Scaling

Scale application instances:

```bash
# Docker Compose
docker-compose -f docker-compose.production.yml up -d --scale crystalcog-app=3

# Kubernetes
kubectl scale deployment crystalcog-app --replicas=3 -n crystalcog-production
```

### Database High Availability

Consider implementing:
- PostgreSQL streaming replication
- Connection pooling with PgBouncer
- Database clustering with Patroni

### Load Balancing

For multiple application instances:
- Use Nginx upstream configuration
- Implement session affinity if needed
- Consider external load balancers (AWS ALB, etc.)

## Maintenance

### Regular Tasks

- **Daily:** Check monitoring dashboards
- **Weekly:** Review logs and error rates
- **Monthly:** Update system packages and certificates
- **Quarterly:** Performance review and capacity planning

### Updates and Patches

```bash
# Update application
git pull origin main
./scripts/production/deploy.sh

# Update system packages
sudo apt update && sudo apt upgrade -y
sudo reboot

# Update Docker images
docker-compose pull
./scripts/production/deploy.sh
```

### Maintenance Mode

```bash
# Enable maintenance mode
docker-compose -f docker-compose.production.yml stop crystalcog-app

# Perform maintenance tasks
# ... maintenance operations ...

# Disable maintenance mode
docker-compose -f docker-compose.production.yml start crystalcog-app
```

## Support and Documentation

### Additional Resources

- [API Documentation](API_DOCUMENTATION.md)
- [Architecture Overview](README_COMPLETE.md)
- [Development Guide](DEVELOPMENT-ROADMAP.md)
- [Security Guidelines](SECURITY.md)

### Getting Help

- Check the [GitHub Issues](https://github.com/EchoCog/crystalcog/issues)
- Review monitoring dashboards for system health
- Consult application logs for error details
- Join the community discussions for support

---

For questions or issues with production deployment, please create an issue in the GitHub repository with:
- Deployment method used (Docker Compose/Kubernetes)
- Error messages and logs
- System configuration details
- Steps to reproduce the issue