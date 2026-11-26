# CrystalCog Production Scripts

This directory contains production deployment and management scripts for CrystalCog.

## Scripts

### `healthcheck.sh` - Production Health Check
A comprehensive health monitoring script that validates the health of all CrystalCog services and system resources.

**Features:**
- ✅ Port connectivity checks for core services (API, CogServer, AtomSpace)
- ✅ HTTP endpoint health verification
- ✅ Process monitoring for critical services
- ✅ System resource monitoring (disk space, memory usage)
- ✅ Log file validation
- ✅ Robust error handling and graceful fallbacks
- ✅ Configurable via environment variables

**Usage:**
```bash
# Basic health check
./healthcheck.sh

# With custom configuration
API_HOST=production-host API_PORT=8080 ./healthcheck.sh
```

**Environment Variables:**
- `API_HOST` - API server hostname (default: localhost)
- `API_PORT` - API server port (default: 5000)
- `COGSERVER_PORT` - CogServer port (default: 17001)
- `ATOMSPACE_PORT` - AtomSpace port (default: 18001)

**Dependencies:**
- `bash` - Shell interpreter
- `curl` - HTTP client for endpoint checks
- `timeout` - Command timeout utility
- `pgrep` - Process search utility
- `df` - Disk space utility
- `free` - Memory usage utility
- `find` - File search utility
- `awk` - Text processing utility
- `sed` - Stream editor

**Return Codes:**
- `0` - All health checks passed
- `1` - One or more health checks failed

**Integration:**
This script is automatically called by `deploy.sh` during deployment to verify service health.

### `deploy.sh` - Production Deployment
Comprehensive deployment script for CrystalCog production environments.

**Features:**
- Docker Compose orchestration
- Automatic backup before deployment
- Health check integration
- Rollback on failure
- Service readiness verification

**Usage:**
```bash
# Deploy with all options
./deploy.sh --environment production --action deploy

# Deploy without backup
./deploy.sh --no-backup

# Deploy with custom timeout
./deploy.sh --timeout 600
```

### `setup-production.sh` - Production Environment Setup
Initial setup script for production environments.

## System Requirements

All scripts are designed to work in standard Unix environments including:
- ✅ Linux distributions (Ubuntu, CentOS, Debian, etc.)
- ✅ Guix System environments
- ✅ Docker containers
- ✅ CI/CD environments

## Guix Compatibility

These scripts are fully compatible with Guix environments and use only standard POSIX utilities that are available in the base Guix system:

- All required commands are available in `(gnu packages base)` and `(gnu packages linux)`
- No external dependencies required beyond standard Unix utilities
- Graceful fallback handling for optional features

## Monitoring and Logging

The health check script provides structured logging with:
- Timestamp-based log entries
- Color-coded status indicators (✓ success, ✗ failure, ⚠ warning)
- Detailed error messages for troubleshooting
- Machine-readable exit codes for automation

## Error Handling

All scripts include robust error handling:
- Graceful degradation for missing optional components
- Clear error messages with actionable information
- Proper exit codes for automation integration
- Fallback behaviors for common failure scenarios

## Security Considerations

- Scripts run with minimal required privileges
- No hardcoded credentials or secrets
- Safe handling of file paths and user input
- Secure command execution practices

## Troubleshooting

### Common Issues

1. **Missing `/app` directory**: The health check script automatically falls back to checking the root filesystem if `/app` is not available.

2. **Service connectivity failures**: Check that services are running and ports are not blocked by firewalls.

3. **Permission issues**: Ensure scripts have execute permissions (`chmod +x *.sh`).

4. **Missing dependencies**: All required commands should be available in standard Unix environments. Install missing packages if needed.

### Debug Mode

Run scripts with debug output:
```bash
bash -x ./healthcheck.sh
```

### Log Analysis

Check system logs for detailed error information:
```bash
# Docker logs
docker compose -f ../../docker-compose.production.yml logs crystalcog-app

# System logs
journalctl -u crystalcog

# Application logs
tail -f /var/log/crystalcog/api.log
```

## Contributing

When modifying production scripts:
1. Maintain backward compatibility
2. Add comprehensive error handling
3. Update this documentation
4. Test in staging environment first
5. Follow existing code style and conventions